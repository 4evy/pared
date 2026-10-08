import AssetBridge
import Darwin
import Foundation

// One diagnostic request per observation batch, including failed requests
// Daemon paths are candidates: only filesystem metadata establishes coverage
final class ModelBrokerInventory {
  private(set) var listings: [String: [String]] = [:]
  private lazy var assets: [[String: Any]]? = {
    guard dlopen(UnifiedAssets.framework, RTLD_NOW) != nil,
      let interface = paredDiagnosticServiceInterface()
    else { return nil }
    let connection = NSXPCConnection(machServiceName: UnifiedAssets.service, options: [])
    connection.remoteObjectInterface = interface
    connection.resume()
    defer { connection.invalidate() }
    let reply = Reply<Data?>()
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
        reply.finish(nil)
      }) as? NSObject
    else { return nil }
    paredDiagnosticAssets(proxy) { data, _ in reply.finish(data) }
    guard let data = reply.wait(timeout: 15) ?? nil else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
  }()

  // List the known type/purpose layout only when every entry is accounted for
  // A missing candidate, extra entry, symlink, or concurrent mutation rejects it
  func entries(in directory: URL) -> [String]? {
    var metadata = stat()
    if lstat(directory.path, &metadata) != 0, errno == ENOENT {
      listings[directory.path] = []
      return []
    }
    guard let assets,
      let rootBefore = ModelDirectoryObservation(directory.path), rootBefore.count == 1
    else {
      return nil
    }
    let purpose = directory.appendingPathComponent("purpose_auto", isDirectory: true)
    guard let before = ModelDirectoryObservation(purpose.path) else { return nil }
    let prefix = purpose.path + "/"
    var names = Set<String>()
    let locations = assets.compactMap { $0["location"] as? String }
    for path in locations where path.hasPrefix(prefix) {
      let suffix = String(path.dropFirst(prefix.count))
      let parts = suffix.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.count == 2, [".AssetData", "AssetData"].contains(parts[1]),
        parts[0].hasSuffix(".asset"), parts[0] != ".asset",
        !parts[0].contains("\0")
      else { continue }
      let name = String(parts[0])
      var metadata = stat()
      guard lstat(purpose.appendingPathComponent(name).path, &metadata) == 0,
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
      else { continue }
      names.insert(name)
    }
    // The catalog name follows the type directory, but its existence and file
    // kind must be observed rather than assumed from Apple's usual layout
    let catalog = directory.lastPathComponent + ".xml"
    metadata = stat()
    if lstat(purpose.appendingPathComponent(catalog).path, &metadata) == 0,
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    {
      names.insert(catalog)
    }
    guard names.count == Int(before.count),
      ModelDirectoryObservation(purpose.path) == before,
      ModelDirectoryObservation(directory.path) == rootBefore
    else { return nil }
    let entries = ["purpose_auto"] + names.sorted().map { "purpose_auto/" + $0 }
    listings[directory.path] = entries
    return entries
  }

  // Metadata is Apple's parsed asset view, not bytes read from Info.plist or
  // the XML catalog; preserve that distinction in the exported report
  func report(assetType: String) -> (object: [String: Any], complete: Bool) {
    let directory = UnifiedAssets.assetDirectory.appendingPathComponent(
      assetType.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
    let entries = entries(in: directory)
    let complete = entries != nil || modelDirectoryIsProvablyEmpty(directory)
    let prefix = directory.path + "/purpose_auto/"
    let reported = (assets ?? []).filter {
      ($0["location"] as? String)?.hasPrefix(prefix) == true
    }
    var object: [String: Any] = [
      "assetType": assetType, "directory": directory.path,
      "directoryListingComplete": complete,
      "metadataFileContentsComplete": false,
      "metadataSource": "Apple asset subscription daemon; not raw file contents",
      "metadataRedactions": ["ArchiveDecryptionKey"],
      "reportedAssets": reported,
    ]
    if let entries { object["directoryEntries"] = entries }
    if !complete {
      object["inventoryError"] =
        "The daemon's reported paths do not account for every directory entry, or directory metadata is unavailable. Reported assets are a partial broker view."
    }
    return (object, complete)
  }
}
