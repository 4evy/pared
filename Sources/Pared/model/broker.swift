import AssetBridge
import Darwin
import Foundation

// One diagnostic request per observation batch, including failed requests
// Daemon paths are candidates: only filesystem metadata establishes coverage
final class ModelBrokerInventory {
  private(set) var listings: [String: [String]] = [:]
  private var diagnosticError: String?
  private lazy var assets: [ParedDiagnosticAsset]? = {
    let reply = Reply<Result<[ParedDiagnosticAsset], Error>>()
    guard
      let service = ParedDiagnosticService(errorHandler: { error in
        reply.finish(.failure(error))
      })
    else {
      diagnosticError = "Required private diagnostic interface is unavailable"
      return nil
    }
    defer { service.invalidate() }
    paredDiagnosticAssets(service) { reply.finish($0) }
    guard let result = reply.wait(timeout: 15) else {
      diagnosticError = "The asset diagnostic request timed out"
      return nil
    }
    do { return try result.get() } catch {
      diagnosticError = error.localizedDescription
      return nil
    }
  }()

  // List the known type/purpose layout only when every entry is accounted for
  // A missing candidate, extra entry, symlink, or concurrent mutation rejects
  // it
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
    let locations = assets.map(\.location)
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
    for name in [catalog, catalog + ".purged"] {
      metadata = stat()
      if lstat(purpose.appendingPathComponent(name).path, &metadata) == 0,
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
      {
        names.insert(name)
      }
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
  func report(assetType: String) -> ModelInventoryReport {
    let directory = UnifiedAssets.assetDirectory.appendingPathComponent(
      assetType.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
    let entries = entries(in: directory)
    let complete = entries != nil || modelDirectoryIsProvablyEmpty(directory)
    let prefix = directory.path + "/purpose_auto/"
    let reported = (assets ?? []).filter {
      $0.location.hasPrefix(prefix)
    }
    return ModelInventoryReport(
      broker: .init(
        assetType: assetType, directory: directory.path, directoryListingComplete: complete,
        reportedAssets: reported.map(ModelReportedAsset.init), directoryEntries: entries,
        diagnosticError: diagnosticError,
        inventoryError: complete
          ? nil
          : "The daemon's reported paths do not account for every directory entry, or directory metadata is unavailable. Reported assets are a partial broker view."
      )
    )
  }
}
