import AssetBridge
import Foundation

struct DownloadedAsset: Encodable {
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

struct LocalDownloadStatus: Encodable {
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

struct ModelStatus: Encodable {
  let assetSet: String
  let assetType: String
  let queryError: String?
  let localSnapshot: LocalDownloadStatus?
  let payloadDirectories: [String]?
  let inventoryError: String?
}

// Retain query errors so callers can distinguish unknown status from absence
// UAF's convenience status method discards the underlying error
func modelStatus(_ targets: [String], catalog: Catalog) throws -> [ModelStatus] {
  guard
    dlopen(
      UnifiedAssets.framework,
      RTLD_NOW) != nil
  else { throw CLIError("Cannot load UnifiedAssetFramework") }
  guard validate(targets, assetTypes: catalog.assetTypes) else {
    throw CLIError("Required asset status interface is unavailable")
  }
  return targets.map { target in
    var queryError: String?
    var snapshot: LocalDownloadStatus?
    do {
      var error: NSError?
      guard let status = ParedLocalStatus(target, &error) else {
        if let error { throw error }
        throw CLIError("Model status returned no result")
      }
      if let error { throw error }
      snapshot = LocalDownloadStatus(status)
    } catch { queryError = String(describing: error) }

    let type = catalog.assetTypes[target]!
    let directory = UnifiedAssets.assetDirectory
      .appendingPathComponent(type.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
    var payloads: [String]?
    var inventoryError: String?
    do {
      // Search nested directories such as purpose_auto, but stop at asset
      // containers. Their contents may be unreadable even when the directory can
      // be listed
      _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      var enumerationError: Error?
      guard
        let entries = FileManager.default.enumerator(
          at: directory, includingPropertiesForKeys: [.isDirectoryKey],
          errorHandler: { _, error in
            enumerationError = error
            return false
          })
      else { throw CLIError("Cannot enumerate \(directory.path)") }
      var paths: [String] = []
      for case let entry as URL in entries {
        if entry.pathExtension == UnifiedAssets.assetExtension,
          try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        {
          paths.append(String(entry.path.dropFirst(directory.path.count + 1)))
          entries.skipDescendants()
        }
      }
      if let error = enumerationError { throw error }
      payloads = paths.sorted()
    } catch { inventoryError = String(describing: error) }
    return ModelStatus(
      assetSet: target, assetType: type, queryError: queryError,
      localSnapshot: snapshot, payloadDirectories: payloads,
      inventoryError: inventoryError)
  }
}
