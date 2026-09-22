import AssetBridge
import Foundation

struct DownloadedAsset: Codable {
  let assetID: String
  let assetType: String
  let assetSpecifier: String
  let assetVersion: String
}

struct LocalDownloadStatus: Codable {
  let latestDownloadedAtomicInstance: String?
  let downloadedAssets: [DownloadedAsset]
  let configuredAssetEntries: Int
  // Apple's selector contains this spelling
  let latestDowloadedAtomicInstanceEntries: Int
  let downloadedNetworkBytes: Int64
  let downloadedFilesystemBytes: Int64
  let vendingAtomicInstanceForConfiguredEntries: Bool
}

struct ModelStatus: Encodable {
  let assetSet: String
  let assetType: String
  let queryError: String?
  let localSnapshot: LocalDownloadStatus?
  let payloadDirectories: [String]?
  let inventoryError: String?
}

// A failed service query does not establish that a model is absent
// Keep the error-bearing primitive: UAF's convenience status method discards it
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
      snapshot = try JSONDecoder().decode(
        LocalDownloadStatus.self, from: JSONSerialization.data(withJSONObject: status))
    } catch { queryError = String(describing: error) }

    let type = catalog.assetTypes[target]!
    let directory = UnifiedAssets.assetDirectory
      .appendingPathComponent(type.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
    var payloads: [String]?
    var inventoryError: String?
    do {
      // Assets can be nested under purpose_auto. Stop at each asset container;
      // its private payload may be unreadable even when inventory is permitted
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
