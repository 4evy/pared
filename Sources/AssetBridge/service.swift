import Foundation
import ObjectiveC

// Operation-specific payloads keep required fields together until serialization
enum BridgeConfiguration {
  case reset(names: NSArray)
  case subscribe(subscriber: NSString, subscriptions: [ParedAssetSubscription])
  case unsubscribe(subscriber: NSString, names: NSArray)

  var dictionary: NSDictionary {
    switch self {
    case .reset(let names):
      ["Operation": "ResetAssetSets", "AssetSets": names]
    case .subscribe(let subscriber, let subscriptions):
      [
        "Operation": "Subscribe", "Subscriber": subscriber,
        "Subscriptions": subscriptions.map(\.native), "UserInitiated": true,
      ]
    case .unsubscribe(let subscriber, let names):
      [
        "Operation": "Unsubscribe", "Subscriber": subscriber,
        "Subscriptions": names, "UserInitiated": true,
      ]
    }
  }
}

// Preserve Apple's interface, oneway signature, and allowed nested classes
func bridgeServiceInterface(
  _ method: BridgeForwardedMethod, requestClasses: [AnyClass] = [],
  replyClasses: [[AnyClass]]
) -> NSXPCInterface? {
  guard paredAssetRuntimeIsAvailable(),
    let type = NSClassFromString("UAFXPCProxyServiceInterface"),
    let interface = objectValue(type, .defaultInterface) as? NSXPCInterface
  else { return nil }
  let selector = method.selector
  let actual = protocol_getMethodDescription(
    interface.protocol, selector, true, true)
  let expected = protocol_getMethodDescription(
    contract(method.serviceContract), selector, true, true)
  guard bridgeSignatureMatches(actual.types, expected.types) else { return nil }
  if !requestClasses.isEmpty {
    let allowed =
      interface.classes(for: selector, argumentIndex: 0, ofReply: false)
      as NSSet
    guard requestClasses.allSatisfy({ allowed.contains($0) }) else {
      return nil
    }
  }
  for (index, required) in replyClasses.enumerated() {
    let allowed =
      interface.classes(for: selector, argumentIndex: index, ofReply: true)
      as NSSet
    guard required.allSatisfy({ allowed.contains($0) }) else { return nil }
  }
  return interface
}

@_cdecl("ParedServiceInterface")
public func paredServiceInterface() -> NSXPCInterface? {
  guard paredAssetRuntimeIsAvailable(),
    let subscription = NSClassFromString("UAFAssetSetSubscription")
  else { return nil }
  return bridgeServiceInterface(
    .operation,
    requestClasses: [
      subscription, NSString.self, NSDictionary.self, NSArray.self, NSNumber.self,
    ],
    replyClasses: [[NSError.self]])
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
    proxy, .reset(names: names), completion, error)
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
    proxy, .subscribe(subscriber: subscriber, subscriptions: subscriptions), completion, error)
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
    proxy, .unsubscribe(subscriber: subscriber, names: names), completion, error)
}

/// Resets named sets for all users, leaving subscriptions intact
/// A successful reply does not prove every payload was deleted; a timeout or
/// transport error can follow daemon effects, so check before retrying
public func paredPerformReset(
  _ service: ParedOperationService, _ sets: [String],
  _ completion: @escaping @Sendable (Error?) -> Void,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard let proxy = service.proxy() else {
    bridgeSetError(error, "Cannot create the operation service proxy; no request sent")
    return false
  }
  return bridgePerformReset(proxy, sets as NSArray, { completion($0) }, error)
}

/// Subscribes validated requests; a successful reply does not promise a
/// download
/// Configuration changes can survive a failed database write
public func paredPerformSubscribe(
  _ service: ParedOperationService, _ subscriber: String, _ subscriptions: [ParedAssetSubscription],
  _ completion: @escaping @Sendable (Error?) -> Void,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard let proxy = service.proxy() else {
    bridgeSetError(error, "Cannot create the operation service proxy; no request sent")
    return false
  }
  return bridgePerformSubscribe(
    proxy, subscriber as NSString, subscriptions as NSArray, { completion($0) }, error)
}

/// Removes named requests; other subscribers can keep requesting the same
/// assets
/// Unreadable stored requests may be skipped as though absent
public func paredPerformUnsubscribe(
  _ service: ParedOperationService, _ subscriber: String, _ names: [String],
  _ completion: @escaping @Sendable (Error?) -> Void,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard let proxy = service.proxy() else {
    bridgeSetError(error, "Cannot create the operation service proxy; no request sent")
    return false
  }
  return bridgePerformUnsubscribe(
    proxy, subscriber as NSString, names as NSArray, { completion($0) }, error)
}
