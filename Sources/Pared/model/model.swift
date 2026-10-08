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
  let directoryEntries: [String]?
  let inventoryError: String?

  var hasErrors: Bool { queryError != nil || inventoryError != nil }
}

func modelInventoryAccessDenied(_ error: Error, depth: Int = 0) -> Bool {
  guard depth < 8 else { return false }
  let error = error as NSError
  if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
    return true
  }
  if error.domain == NSPOSIXErrorDomain && (error.code == Int(EACCES) || error.code == Int(EPERM)) {
    return true
  }
  guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
  return modelInventoryAccessDenied(underlying, depth: depth + 1)
}

// Missing directories and metadata-proven empty layouts contain no payloads
// Broker paths require complete metadata coverage; unknown layouts stay errors
func modelPayloadDirectories(
  assetType: String, root: URL = UnifiedAssets.assetDirectory,
  broker: ModelBrokerInventory? = nil
) throws -> [String] {
  let directory = root.appendingPathComponent(
    assetType.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
  do {
    guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw CLIError("Cannot verify model folders through a symbolic link: \(directory.path)")
    }
    _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
  } catch {
    if modelInventoryAccessDenied(error), modelDirectoryIsProvablyEmpty(directory) {
      return []
    }
    if modelInventoryAccessDenied(error), root == UnifiedAssets.assetDirectory,
      let entries = (broker ?? ModelBrokerInventory()).entries(in: directory)
    {
      return entries.filter { $0.hasSuffix(".asset") }
    }
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
  let broker = ModelBrokerInventory()
  return assets.map { asset in
    var payloads: [String]?
    var inventoryError: String?
    do {
      payloads = try modelPayloadDirectories(assetType: asset.assetType, broker: broker)
    } catch {
      inventoryError =
        modelInventoryAccessDenied(error)
        ? "macOS denied access to the model folder, and a complete broker inventory could not be verified. System-protected model storage can require restricted entitlements that sudo and Full Disk Access cannot supply. Folder inventory is unavailable; this does not show whether models are in use."
        : error.localizedDescription
    }
    // An empty inventory needs no atomic-instance lock or download snapshot
    if payloads?.isEmpty == true {
      return ModelStatus(
        assetSet: asset.name, assetType: asset.assetType, queryError: nil,
        localSnapshot: nil, payloadDirectories: [], directoryEntries: nil, inventoryError: nil)
    }
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

    let directory = UnifiedAssets.assetDirectory.appendingPathComponent(
      asset.assetType.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
    return ModelStatus(
      assetSet: asset.name, assetType: asset.assetType, queryError: queryError,
      localSnapshot: snapshot, payloadDirectories: payloads,
      directoryEntries: broker.listings[directory.path],
      inventoryError: inventoryError)
  }
}
