import Darwin
import Foundation
import ObjectiveC

typealias BridgeError = AutoreleasingUnsafeMutablePointer<NSError?>?
typealias BridgeCompletion = @convention(block) (NSError?) -> Void

func contract(_ name: String) -> Protocol {
  bridgeContracts[name]!
}

@_cdecl("ParedSignatureMatches")
public func bridgeSignatureMatches(
  _ actual: UnsafePointer<CChar>?, _ expected: UnsafePointer<CChar>?
) -> Bool {
  guard let actual, let expected, let type = NSClassFromString("NSMethodSignature") else {
    return false
  }
  let selector = NSSelectorFromString("signatureWithObjCTypes:")
  typealias Signature =
    @convention(c) (AnyObject, Selector, UnsafePointer<CChar>) -> Unmanaged<AnyObject>?
  let call = unsafeBitCast(
    class_getMethodImplementation(object_getClass(type), selector), to: Signature.self)
  guard let lhs = call(type, selector, actual)?.takeUnretainedValue() as? NSObject,
    let rhs = call(type, selector, expected)?.takeUnretainedValue()
  else { return false }
  return lhs.isEqual(rhs)
}

@_cdecl("ParedMethodMatches")
public func bridgeMethodMatches(
  _ method: Method?, _ selector: Selector, _ contract: Protocol, _ instance: Bool
) -> Bool {
  let expected = protocol_getMethodDescription(contract, selector, true, instance)
  guard let method else { return false }
  return bridgeSignatureMatches(method_getTypeEncoding(method), expected.types)
}

func bridgeHasMethod(_ object: AnyObject?, _ selector: Selector, _ contract: Protocol)
  -> Bool
{
  guard let object, let receiver = object_getClass(object) else { return false }
  return bridgeMethodMatches(
    class_getInstanceMethod(receiver, selector), selector, contract, !object_isClass(object))
}

private func declaredMethodsMatch(_ receiver: AnyClass?, _ contract: Protocol, _ instance: Bool)
  -> Bool
{
  guard let receiver else { return false }
  var count: UInt32 = 0
  guard let methods = protocol_copyMethodDescriptionList(contract, true, instance, &count) else {
    return false
  }
  defer { free(methods) }
  guard count > 0 else { return false }
  return UnsafeBufferPointer(start: methods, count: Int(count)).allSatisfy { expected in
    guard let selector = expected.name,
      let method = class_getInstanceMethod(receiver, selector)
    else { return false }
    return bridgeSignatureMatches(method_getTypeEncoding(method), expected.types)
  }
}

func bridgeHasDeclaredMethods(_ object: AnyObject?, _ contract: Protocol) -> Bool {
  guard let object else { return false }
  return declaredMethodsMatch(object_getClass(object), contract, !object_isClass(object))
}

func bridgeInstancesHaveDeclaredMethods(_ type: AnyClass?, _ contract: Protocol) -> Bool {
  declaredMethodsMatch(type, contract, true)
}

func hasMethod(_ object: AnyObject?, _ selector: String, _ name: String) -> Bool {
  bridgeHasMethod(object, NSSelectorFromString(selector), contract(name))
}

func hasMethods(_ object: AnyObject?, _ name: String) -> Bool {
  bridgeHasDeclaredMethods(object, contract(name))
}

// The caller checks each private method's encoding before reaching these calls
// Unmanaged preserves Objective-C's +0 getter and +1 initializer conventions
private func implementation(_ object: AnyObject, _ selector: Selector) -> IMP {
  class_getMethodImplementation(object_getClass(object), selector)!
}

func objectValue(_ object: AnyObject, _ name: String) -> AnyObject? {
  let selector = NSSelectorFromString(name)
  typealias Call = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation(object, selector), to: Call.self)(object, selector)?
    .takeUnretainedValue()
}

func objectValue(_ object: AnyObject, _ name: String, _ value: NSString) -> AnyObject? {
  let selector = NSSelectorFromString(name)
  typealias Call = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation(object, selector), to: Call.self)(object, selector, value)?
    .takeUnretainedValue()
}

func aliasValue(_ manager: AnyObject, _ alias: NSString, _ value: NSString) -> AnyObject? {
  let selector = NSSelectorFromString("getAssetSetUsagesForUsageAlias:usageAliasValue:")
  typealias Call = @convention(c) (AnyObject, Selector, NSString, NSString) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation(manager, selector), to: Call.self)(
    manager, selector, alias, value)?.takeUnretainedValue()
}

func initializeSubscription(
  _ type: AnyClass, _ name: NSString, _ sets: NSDictionary, _ aliases: NSDictionary
) -> AnyObject? {
  let allocate = NSSelectorFromString("alloc")
  typealias Allocate = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
  guard
    let allocated = unsafeBitCast(implementation(type, allocate), to: Allocate.self)(type, allocate)
  else { return nil }
  let selector = NSSelectorFromString("initWithName:assetSets:usageAliases:")
  typealias Initialize =
    @convention(c) (AnyObject, Selector, NSString, NSDictionary, NSDictionary) -> Unmanaged<
      AnyObject
    >?
  // init consumes alloc's ownership, including nil and replacement-object returns
  let object = allocated.takeUnretainedValue()
  // alloc may return a different class; check the receiver before calling its IMP
  guard hasMethod(object, "initWithName:assetSets:usageAliases:", "ParedSubscriptionAPI") else {
    allocated.release()
    return nil
  }
  return unsafeBitCast(implementation(object, selector), to: Initialize.self)(
    object, selector, name, sets, aliases)?.takeRetainedValue()
}

func validateSubscription(_ object: AnyObject, _ manager: AnyObject, _ error: inout AnyObject?)
  -> Bool
{
  let selector = NSSelectorFromString("isValid:error:")
  typealias Call =
    @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<AnyObject?>)
    -> Bool
  return unsafeBitCast(implementation(object, selector), to: Call.self)(
    object, selector, manager, &error)
}

func latestStatus(_ type: AnyClass, _ name: NSString, _ error: inout AnyObject?) -> AnyObject? {
  let selector = NSSelectorFromString("latestStatusForClients:error:")
  typealias Call =
    @convention(c) (AnyObject, Selector, NSString, AutoreleasingUnsafeMutablePointer<AnyObject?>) ->
    Unmanaged<AnyObject>?
  return unsafeBitCast(implementation(type, selector), to: Call.self)(type, selector, name, &error)?
    .takeUnretainedValue()
}

func scalarBool(_ object: AnyObject, _ name: String) -> Bool {
  let selector = NSSelectorFromString(name)
  typealias Call = @convention(c) (AnyObject, Selector) -> Bool
  return unsafeBitCast(implementation(object, selector), to: Call.self)(object, selector)
}

func scalarInt64(_ object: AnyObject, _ name: String) -> Int64 {
  let selector = NSSelectorFromString(name)
  typealias Call = @convention(c) (AnyObject, Selector) -> Int64
  return unsafeBitCast(implementation(object, selector), to: Call.self)(object, selector)
}

func sendConfiguration(
  _ proxy: NSObject?, _ configuration: NSDictionary, _ completion: BridgeCompletion?,
  _ error: BridgeError
) -> Bool {
  guard let proxy, let completion else {
    bridgeSetError(error, "A request requires a proxy and completion; no request sent")
    return false
  }
  // XPC forwards this selector, so use message dispatch rather than its IMP
  // The interface is checked when opening the connection
  typealias Send = @convention(c) (AnyObject, Selector, NSDictionary, BridgeCompletion) -> Void
  let send = unsafeBitCast(
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!, to: Send.self)
  send(proxy, NSSelectorFromString("operationWithConfig:completion:"), configuration, completion)
  return true
}

func bridgeSetError(
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?, _ message: NSString
) {
  error?.pointee = NSError(
    domain: "org.pared", code: 69, userInfo: [NSLocalizedDescriptionKey: message])
}

func bridgeSetReturnedError(
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?, _ returned: AnyObject?
) {
  guard let returned = returned as? NSError else {
    bridgeSetError(error, "Apple returned an unsupported error object")
    return
  }
  error?.pointee = returned
}

func bridgeNonemptyString(_ value: AnyObject?) -> Bool {
  guard let string = value as? NSString else { return false }
  return string.length != 0
}

func bridgeHasNonemptyStrings(_ values: AnyObject?) -> Bool {
  guard let values = values as? [NSString] else { return false }
  return values.allSatisfy { $0.length != 0 }
}

func bridgeCopyStringValues(_ values: AnyObject?) -> NSDictionary? {
  guard let values = values as? NSDictionary else { return nil }
  let result = NSMutableDictionary(capacity: values.count)
  for (key, value) in values {
    guard let key = key as? NSString, let value = value as? NSString else { return nil }
    result[key.copy() as! NSString] = value.copy()
  }
  return result.copy() as? NSDictionary
}

func bridgeCopyAssetSetUsages(_ sets: AnyObject?) -> NSDictionary? {
  guard let sets = sets as? NSDictionary else { return nil }
  let result = NSMutableDictionary(capacity: sets.count)
  // Native initializers retain nested dictionaries, so freeze every level
  for (key, value) in sets {
    guard let key = key as? NSString, let usages = bridgeCopyStringValues(value as AnyObject) else {
      return nil
    }
    result[key.copy() as! NSString] = usages
  }
  return result.copy() as? NSDictionary
}
