import Foundation

private func downloadedAsset(_ entry: AnyObject, _ error: BridgeError) -> ParedDownloadedAsset? {
  guard hasMethods(entry, "ParedDownloadedEntryAPI") else {
    bridgeSetError(error, "Unknown downloaded asset entry interface")
    return nil
  }
  guard let selector = objectValue(entry, "fullAssetSelector"),
    hasMethods(selector, "ParedAutoAssetSelectorAPI")
  else {
    bridgeSetError(error, "Unknown downloaded asset selector interface")
    return nil
  }
  let id = objectValue(entry, "assetID")
  let type = objectValue(selector, "assetType")
  let specifier = objectValue(selector, "assetSpecifier")
  let version = objectValue(selector, "assetVersion")
  guard [id, type, specifier, version].allSatisfy(bridgeNonemptyString) else {
    bridgeSetError(error, "Unknown downloaded asset value types")
    return nil
  }
  return ParedDownloadedAsset(
    id: id as! String, type: type as! String, specifier: specifier as! String,
    version: version as! String)
}

@_cdecl("ParedLocalStatus")
public func bridgeLocalStatus(
  _ name: AnyObject?, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> ParedLocalDownloadStatus? {
  guard bridgeNonemptyString(name), let name = name as? NSString else {
    bridgeSetError(error, "Local status requires a nonempty asset set name")
    return nil
  }
  guard let type = NSClassFromString("UAFAutoAssetManager"),
    hasMethod(type, "latestStatusForClients:error:", "ParedAutoAssetManagerAPI")
  else {
    bridgeSetError(error, "Local asset status interface is unavailable")
    return nil
  }
  var returnedError: AnyObject?
  let result = latestStatus(type, name, &returnedError)
  if let returnedError {
    bridgeSetReturnedError(error, returnedError)
    return nil
  }
  guard let status = result else {
    bridgeSetError(error, "Apple returned no local asset status")
    return nil
  }
  guard hasMethods(status, "ParedAssetSetStatusObjectsAPI") else {
    bridgeSetError(error, "Unknown asset status object interface")
    return nil
  }
  guard hasMethods(status, "ParedAssetSetStatusScalarsAPI") else {
    bridgeSetError(error, "Unknown asset status scalar interface")
    return nil
  }
  let instance = objectValue(status, "latestDownloadedAtomicInstance")
  let configured = objectValue(status, "configuredAssetEntries")
  let downloaded = objectValue(status, "latestDowloadedAtomicInstanceEntries")
  guard instance == nil || instance is NSString, let configured = configured as? NSArray,
    let downloaded = downloaded as? NSArray
  else {
    bridgeSetError(error, "Unknown asset status value types")
    return nil
  }
  let configuredType: AnyClass? = NSClassFromString("MAAutoAssetSetEntry")
  for entry in configured {
    guard let configuredType, let entry = entry as? NSObject, entry.isKind(of: configuredType)
    else {
      bridgeSetError(error, "Unknown configured asset entry class")
      return nil
    }
  }
  var assets: [ParedDownloadedAsset] = []
  for entry in downloaded {
    guard let asset = downloadedAsset(entry as AnyObject, error) else { return nil }
    assets.append(asset)
  }
  // Read each private getter once; query/release errors reject even a status
  return ParedLocalDownloadStatus(
    instance: instance as? String, configured: configured.count, assets: assets,
    network: scalarInt64(status, "downloadedNetworkBytes"),
    filesystem: scalarInt64(status, "downloadedFilesystemBytes"),
    vending: scalarBool(status, "vendingAtomicInstanceForConfiguredEntries"))
}

/// Queries the latest downloaded instance and rejects query or lock-release
/// errors
/// The returned snapshot holds no lock, so its files can disappear afterward
public func paredLocalStatus(_ name: String, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?)
  -> ParedLocalDownloadStatus?
{
  bridgeLocalStatus(name as NSString, error)
}
