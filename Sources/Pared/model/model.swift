import AssetBridge
import Foundation

struct DownloadedAsset: Codable {
  let assetID: String
  let assetType: String
  let assetSpecifier: String
  let assetVersion: String

  init(_ asset: ParedDownloadedAsset) {
    assetID = asset.assetID
    assetType = asset.assetType
    assetSpecifier = asset.assetSpecifier
    assetVersion = asset.assetVersion
  }
}

struct LocalDownloadStatus: Codable {
  let latestDownloadedAtomicInstance: String?
  let downloadedAssets: [DownloadedAsset]
  let configuredAssetEntries: Int
  // Preserve Apple's misspelled selector name in the bridge's JSON output
  let latestDowloadedAtomicInstanceEntries: Int
  let downloadedNetworkBytes: Int64
  let downloadedFilesystemBytes: Int64
  let vendingAtomicInstanceForConfiguredEntries: Bool

  init(_ status: ParedLocalDownloadStatus) {
    latestDownloadedAtomicInstance = status.latestDownloadedAtomicInstance
    downloadedAssets = status.downloadedAssets.map(DownloadedAsset.init)
    configuredAssetEntries = Int(status.configuredAssetEntries)
    latestDowloadedAtomicInstanceEntries = Int(status.latestDowloadedAtomicInstanceEntries)
    downloadedNetworkBytes = status.downloadedNetworkBytes
    downloadedFilesystemBytes = status.downloadedFilesystemBytes
    vendingAtomicInstanceForConfiguredEntries = status.vendingAtomicInstanceForConfiguredEntries
  }
}

struct ModelStatus: Codable {
  let assetSet: String
  let assetType: String
  let queryError: String?
  let localSnapshot: LocalDownloadStatus?
  let payloadDirectories: [String]?
  let inventoryError: String?

  var hasErrors: Bool { queryError != nil || inventoryError != nil }
}

// A missing type directory means no payloads; unreadable directories remain
// errors so cleanup cannot mistake denied access for successful removal
func modelPayloadDirectories(
  assetType: String, root: URL = UnifiedAssets.assetDirectory
) throws -> [String] {
  let directory = root.appendingPathComponent(
    assetType.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
  do {
    guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CLIError("Cannot verify model folders through a symbolic link: \(directory.path)")
    }
    _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
  } catch {
    let fileError = error as NSError
    if fileError.domain == NSCocoaErrorDomain && fileError.code == NSFileReadNoSuchFileError {
      return []
    }
    throw error
  }
  var enumerationError: Error?
  guard
    let entries = FileManager.default.enumerator(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      errorHandler: { _, error in
        enumerationError = error
        return false
      })
  else { throw CLIError("Cannot enumerate \(directory.path)") }
  var paths: [String] = []
  for case let entry as URL in entries {
    let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    // Enumeration skips linked directories, which can hide remaining payloads
    guard values.isSymbolicLink != true else {
      throw CLIError("Cannot verify model folders through a symbolic link: \(entry.path)")
    }
    if entry.pathExtension == UnifiedAssets.assetExtension,
      values.isDirectory == true
    {
      // Enumeration can expand /var to /private/var, so use its relative depth
      paths.append(entry.pathComponents.suffix(entries.level).joined(separator: "/"))
      entries.skipDescendants()
    }
  }
  if let error = enumerationError { throw error }
  return paths.sorted()
}

// Retain query errors so callers can distinguish unknown status from absence
// UAF's convenience status method discards the underlying error
func modelStatus(_ targets: [String], catalog: Catalog) throws -> [ModelStatus] {
  guard
    dlopen(
      UnifiedAssets.framework,
      RTLD_NOW) != nil
  else { throw CLIError("Cannot load UnifiedAssetFramework") }
  let assets = try catalog.modelAssets(targets)
  for asset in assets { try asset.validateConfiguration() }
  return assets.map { asset in
    var queryError: String?
    var snapshot: LocalDownloadStatus?
    do {
      var error: NSError?
      guard let status = paredLocalStatus(asset.name, &error) else {
        if let error { throw error }
        throw CLIError("Model status returned no result")
      }
      if let error { throw error }
      snapshot = LocalDownloadStatus(status)
    } catch { queryError = String(describing: error) }

    var payloads: [String]?
    var inventoryError: String?
    do {
      // Stop at asset containers because their contents can be unreadable
      payloads = try modelPayloadDirectories(assetType: asset.assetType)
    } catch { inventoryError = String(describing: error) }
    return ModelStatus(
      assetSet: asset.name, assetType: asset.assetType, queryError: queryError,
      localSnapshot: snapshot, payloadDirectories: payloads,
      inventoryError: inventoryError)
  }
}
