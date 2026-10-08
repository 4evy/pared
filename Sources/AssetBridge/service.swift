import Foundation
import ObjectiveC

@_cdecl("ParedServiceInterface")
public func paredServiceInterface() -> NSXPCInterface? {
  guard let type = NSClassFromString("UAFXPCProxyServiceInterface"),
    hasMethod(type, "defaultInterface", "ParedServiceInterfaceAPI"),
    let interface = objectValue(type, "defaultInterface") as? NSXPCInterface
  else { return nil }
  let operation = NSSelectorFromString("operationWithConfig:completion:")
  let actual = protocol_getMethodDescription(interface.protocol, operation, true, true)
  let expected = protocol_getMethodDescription(contract("ParedServiceAPI"), operation, true, true)
  guard bridgeSignatureMatches(actual.types, expected.types),
    let subscription = NSClassFromString("UAFAssetSetSubscription")
  else { return nil }
  // Preserve Apple's interface and allowed classes for nested native objects
  let request = interface.classes(for: operation, argumentIndex: 0, ofReply: false) as NSSet
  let required: [AnyClass] = [
    subscription, NSString.self, NSDictionary.self, NSArray.self, NSNumber.self,
  ]
  guard required.allSatisfy({ request.contains($0) }),
    (interface.classes(for: operation, argumentIndex: 0, ofReply: true) as NSSet).contains(
      NSError.self)
  else { return nil }
  return interface
}

private func copiedNames(_ values: AnyObject?) -> NSArray? {
  guard bridgeHasNonemptyStrings(values), let values = values as? NSArray else { return nil }
  let snapshot = NSArray(array: values as! [Any], copyItems: true)
  // NSString preserves distinct Unicode spellings used as daemon request keys
  // Copy before XPC defers serialization and retain Foundation's sort order
  return NSArray(array: NSSet(array: snapshot as! [Any]).allObjects)
    .sortedArray(using: NSSelectorFromString("compare:")) as NSArray
}

@_cdecl("ParedPerformReset")
public func bridgePerformReset(
  _ proxy: NSObject?, _ assetSets: AnyObject?,
  _ completion: (@convention(block) (NSError?) -> Void)?,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  // Omitting AssetSets resets every set; require explicit nonempty names
  guard let names = copiedNames(assetSets), names.count > 0 else {
    bridgeSetError(error, "Reset requires explicit nonempty asset set names; no request sent")
    return false
  }
  return sendConfiguration(
    proxy, ["Operation": "ResetAssetSets", "AssetSets": names], completion, error)
}

@_cdecl("ParedPerformSubscribe")
public func bridgePerformSubscribe(
  _ proxy: NSObject?, _ subscriber: AnyObject?, _ subscriptions: AnyObject?,
  _ completion: (@convention(block) (NSError?) -> Void)?,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard bridgeNonemptyString(subscriber),
    let subscriber = (subscriber as? NSString)?.copy() as? NSString,
    let subscriptions = subscriptions as? NSArray, subscriptions.count > 0
  else {
    bridgeSetError(
      error, "Subscribe requires a subscriber and validated subscriptions; no request sent")
    return false
  }
  guard let subscriptions = subscriptions as? [ParedAssetSubscription] else {
    bridgeSetError(error, "Unknown subscription wrapper; no request sent")
    return false
  }
  // NSString preserves distinct Unicode spellings used as daemon request keys
  guard Set(subscriptions.map(\.name)).count == subscriptions.count else {
    bridgeSetError(error, "Duplicate subscription name; no request sent")
    return false
  }
  return sendConfiguration(
    proxy,
    [
      "Operation": "Subscribe", "Subscriber": subscriber,
      "Subscriptions": subscriptions.map(\.native), "UserInitiated": true,
    ], completion, error)
}

@_cdecl("ParedPerformUnsubscribe")
public func bridgePerformUnsubscribe(
  _ proxy: NSObject?, _ subscriber: AnyObject?, _ names: AnyObject?,
  _ completion: (@convention(block) (NSError?) -> Void)?,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard bridgeNonemptyString(subscriber),
    let subscriber = (subscriber as? NSString)?.copy() as? NSString,
    let names = copiedNames(names), names.count > 0
  else {
    bridgeSetError(
      error, "Unsubscribe requires a subscriber and subscription names; no request sent")
    return false
  }
  return sendConfiguration(
    proxy,
    [
      "Operation": "Unsubscribe", "Subscriber": subscriber,
      "Subscriptions": names, "UserInitiated": true,
    ], completion, error)
}

/// Resets named sets for all users, leaving subscriptions intact
/// A successful reply does not prove every payload was deleted; a timeout or
/// transport error can follow daemon effects, so check before retrying
public func paredPerformReset(
  _ proxy: NSObject, _ sets: [String], _ completion: @escaping (Error?) -> Void,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  bridgePerformReset(proxy, sets as NSArray, { completion($0) }, error)
}

/// Subscribes validated requests; a successful reply does not promise a download
/// Configuration changes can survive a failed database write
public func paredPerformSubscribe(
  _ proxy: NSObject, _ subscriber: String, _ subscriptions: [ParedAssetSubscription],
  _ completion: @escaping (Error?) -> Void, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  bridgePerformSubscribe(
    proxy, subscriber as NSString, subscriptions as NSArray, { completion($0) }, error)
}

/// Removes named requests; other subscribers can keep requesting the same assets
/// Unreadable stored requests may be skipped as though absent
public func paredPerformUnsubscribe(
  _ proxy: NSObject, _ subscriber: String, _ names: [String],
  _ completion: @escaping (Error?) -> Void, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  bridgePerformUnsubscribe(
    proxy, subscriber as NSString, names as NSArray, { completion($0) }, error)
}
