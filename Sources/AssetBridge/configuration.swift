import Foundation

func bridgeConfigurationManager() -> AnyObject? {
  guard paredAssetRuntimeIsAvailable(), let type = NSClassFromString("UAFConfigurationManager")
  else { return nil }
  return objectValue(type, .defaultManager)
}

func bridgeAssetSetWithManager(_ manager: AnyObject?, _ name: NSString?) -> AnyObject? {
  guard bridgeNonemptyString(name), let name, let manager else { return nil }
  return objectValue(manager, .assetSet, name)
}

func bridgeEnabledUsagesMatchConfiguration(_ sets: NSDictionary, _ manager: AnyObject)
  -> Bool
{
  for (name, usages) in sets {
    guard let name = name as? NSString,
      let usages = usages as? NSDictionary,
      let set = bridgeAssetSetWithManager(manager, name), hasMethods(set, .assetSetUsage)
    else { return false }
    let names = objectValue(set, .usageTypes)
    let restrictions = objectValue(set, .usageValues)
    guard bridgeHasNonemptyStrings(names), restrictions == nil || restrictions is NSDictionary
    else { return false }
    for usage in usages.allKeys {
      let values = (restrictions as? NSDictionary)?[usage] as AnyObject?
      guard (names as! NSArray).contains(usage),
        values == nil
          || (bridgeHasNonemptyStrings(values) && (values as! NSArray).contains("ENABLED"))
      else { return false }
    }
  }
  return true
}

func bridgeResolveAliasWithManager(
  _ manager: AnyObject?, _ alias: AnyObject?, _ value: AnyObject?
) -> NSDictionary? {
  guard bridgeNonemptyString(alias), let alias = alias as? NSString,
    let value = value as? NSString, let manager
  else { return nil }
  return bridgeCopyAssetSetUsages(aliasValue(manager, alias, value))
}

@_cdecl("ParedAssetTypeForSet")
public func bridgeAssetTypeForSet(_ name: NSString?) -> NSString? {
  guard let set = bridgeAssetSetWithManager(bridgeConfigurationManager(), name)
  else { return nil }
  let value = objectValue(set, .autoAssetType)
  return bridgeNonemptyString(value) ? (value as! NSString).copy() as? NSString : nil
}

@_cdecl("ParedUsageTypesForSet")
public func bridgeUsageTypesForSet(_ name: NSString?) -> NSArray? {
  guard let set = bridgeAssetSetWithManager(bridgeConfigurationManager(), name)
  else { return nil }
  let values = objectValue(set, .usageTypes)
  guard bridgeHasNonemptyStrings(values) else { return nil }
  return NSArray(array: values as! [Any], copyItems: true)
}

@_cdecl("ParedResolveUsageAlias")
public func bridgeResolveUsageAlias(_ alias: AnyObject?, _ value: AnyObject?) -> NSDictionary? {
  // Expansions can include dependencies in other sets and deprecated values
  bridgeResolveAliasWithManager(bridgeConfigurationManager(), alias, value)
}

public func paredAssetTypeForSet(_ name: String) -> String? {
  bridgeAssetTypeForSet(name as NSString) as String?
}
public func paredUsageTypesForSet(_ name: String) -> [String]? {
  bridgeUsageTypesForSet(name as NSString) as? [String]
}
public func paredResolveUsageAlias(_ alias: String, _ value: String) -> [String: [String: String]]?
{ bridgeResolveUsageAlias(alias as NSString, value as NSString) as? [String: [String: String]] }
