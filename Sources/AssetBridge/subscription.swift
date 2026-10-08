import Foundation
import ObjectiveC

private func hasEnabledUsages(_ sets: NSDictionary) -> Bool {
  sets.allValues.allSatisfy { value in
    guard let usages = value as? NSDictionary, usages.count > 0 else { return false }
    return usages.allValues.allSatisfy { ($0 as? String) == "ENABLED" }
  }
}

private func validatedNativeSubscription(
  _ name: NSString, _ sets: NSDictionary, _ aliases: NSDictionary, _ manager: AnyObject,
  _ error: BridgeError
) -> AnyObject? {
  guard let type = NSClassFromString("UAFAssetSetSubscription"),
    bridgeMethodMatches(
      class_getInstanceMethod(type, NSSelectorFromString("initWithName:assetSets:usageAliases:")),
      NSSelectorFromString("initWithName:assetSets:usageAliases:"),
      contract("ParedSubscriptionAPI"), true),
    hasMethod(type, "supportsSecureCoding", "NSSecureCoding"),
    bridgeInstancesHaveDeclaredMethods(type, contract("NSCoding")),
    scalarBool(type, "supportsSecureCoding")
  else {
    bridgeSetError(
      error, "Required subscription initializer or secure coding interface is unavailable")
    return nil
  }
  guard let native = initializeSubscription(type, name, sets, aliases),
    let object = native as? NSObject, object.isKind(of: type),
    hasMethod(native, "isValid:error:", "ParedSubscriptionAPI")
  else {
    bridgeSetError(error, "Required subscription validation interface is unavailable")
    return nil
  }
  guard hasMethods(native, "ParedSubscriptionValuesAPI") else {
    bridgeSetError(error, "Required subscription value interface is unavailable")
    return nil
  }
  // Check what will be serialized: a compatible ABI does not prove values match
  guard let storedName = objectValue(native, "name") as? NSString,
    storedName.isEqual(to: name as String),
    let storedSets = objectValue(native, "assetSets") as? NSDictionary, storedSets.isEqual(sets),
    let storedAliases = objectValue(native, "usageAliases") as? NSDictionary,
    storedAliases.isEqual(aliases),
    objectValue(native, "expiration") == nil
  else {
    bridgeSetError(error, "Apple returned unsupported subscription values")
    return nil
  }
  // Start with a fresh error because Apple's validator may chain it
  var returnedError: AnyObject?
  let valid = validateSubscription(native, manager, &returnedError)
  guard valid, returnedError == nil else {
    if let returnedError {
      bridgeSetReturnedError(error, returnedError)
    } else {
      bridgeSetError(error, "Apple rejected the download subscription")
    }
    return nil
  }
  return native
}

@_cdecl("ParedSubscription")
public func bridgeSubscription(
  _ name: AnyObject?, _ assetSetUsages: AnyObject?, _ usageAliases: AnyObject?,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> ParedAssetSubscription? {
  guard bridgeNonemptyString(name), let name = (name as? NSString)?.copy() as? NSString else {
    bridgeSetError(error, "A download subscription requires a nonempty name")
    return nil
  }
  guard let sets = bridgeCopyAssetSetUsages(assetSetUsages),
    let aliases = bridgeCopyStringValues(usageAliases),
    sets.count > 0 || aliases.count > 0, hasEnabledUsages(sets)
  else {
    bridgeSetError(
      error, "A download subscription requires a name and nonempty ENABLED usages or aliases")
    return nil
  }
  guard let manager = bridgeConfigurationManager() else {
    bridgeSetError(error, "Download configuration interface is unavailable")
    return nil
  }
  // Apple's validator assumes valid getters and collections and misses some
  // value restrictions. Check those before it can silently drop usages
  guard bridgeEnabledUsagesMatchConfiguration(sets, manager) else {
    bridgeSetError(error, "Download usages no longer permit ENABLED values")
    return nil
  }
  for (alias, value) in aliases {
    guard
      let resolved = bridgeResolveAliasWithManager(manager, alias as? NSString, value as? NSString),
      resolved.count > 0, hasEnabledUsages(resolved),
      bridgeEnabledUsagesMatchConfiguration(resolved, manager)
    else {
      bridgeSetError(error, "Download alias did not resolve to supported ENABLED usages")
      return nil
    }
  }
  guard let native = validatedNativeSubscription(name, sets, aliases, manager, error) else {
    return nil
  }
  return ParedAssetSubscription(native: native, name: name)
}

/// Copies caller inputs and validates the native object before sending requests
/// Subscriptions have no expiration; unsubscribe explicitly to remove them
public func paredSubscription(
  _ name: String, _ sets: [String: [String: String]], _ aliases: [String: String],
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> ParedAssetSubscription? {
  bridgeSubscription(name as NSString, sets as NSDictionary, aliases as NSDictionary, error)
}
