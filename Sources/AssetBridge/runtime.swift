import Darwin
import Foundation
import ObjectiveC

typealias BridgeError = AutoreleasingUnsafeMutablePointer<NSError?>?
typealias BridgeCompletion = @convention(block) (NSError?) -> Void

private let assetRuntimeAvailable =
  dlopen(
    "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework",
    RTLD_NOW) != nil

/// Loads the framework once and keeps its native classes available
/// Individual bridge operations also validate their required signatures
public func paredAssetRuntimeIsAvailable() -> Bool { assetRuntimeAvailable }

func contract(_ name: BridgeContract) -> Protocol {
  bridgeContracts[name]!
}

// Diagnostic callers can name a contract, but dispatch uses the closed enum
func contract(_ name: String) -> Protocol {
  guard let declaration = BridgeContract(rawValue: name) else {
    preconditionFailure("Unknown bridge contract")
  }
  return contract(declaration)
}

private func methodSignature(_ encoding: UnsafePointer<CChar>?) -> NSObject? {
  guard let encoding, let type = NSClassFromString("NSMethodSignature") else {
    return nil
  }
  let selector = NSSelectorFromString("signatureWithObjCTypes:")
  guard let metaclass = object_getClass(type),
    let factory = class_getInstanceMethod(metaclass, selector)
  else { return nil }
  typealias Signature =
    @convention(c) (AnyObject, Selector, UnsafePointer<CChar>) -> Unmanaged<AnyObject>?
  let call = unsafeBitCast(method_getImplementation(factory), to: Signature.self)
  return call(type, selector, encoding)?.takeUnretainedValue() as? NSObject
}

@_cdecl("ParedSignatureMatches")
public func bridgeSignatureMatches(
  _ actual: UnsafePointer<CChar>?, _ expected: UnsafePointer<CChar>?
) -> Bool {
  guard let lhs = methodSignature(actual), let rhs = methodSignature(expected) else { return false }
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

func hasMethod(_ object: AnyObject?, _ selector: String, _ name: BridgeContract) -> Bool {
  bridgeHasMethod(object, NSSelectorFromString(selector), contract(name))
}

func hasMethods(_ object: AnyObject?, _ name: BridgeContract) -> Bool {
  bridgeHasDeclaredMethods(object, contract(name))
}

// Resolve and validate the same Method whose IMP will be called
// Unmanaged preserves Objective-C's +0 getter and +1 initializer conventions
private func implementation(
  _ object: AnyObject, _ selector: Selector, _ contractName: BridgeContract
) -> IMP? {
  guard let receiver = object_getClass(object),
    let method = class_getInstanceMethod(receiver, selector),
    bridgeMethodMatches(method, selector, contract(contractName), !object_isClass(object))
  else { return nil }
  return method_getImplementation(method)
}

func objectValue(_ object: AnyObject, _ getter: BridgeObjectGetter) -> AnyObject? {
  let selector = NSSelectorFromString(getter.rawValue)
  guard let implementation = implementation(object, selector, getter.contractName) else {
    return nil
  }
  typealias Call = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation, to: Call.self)(object, selector)?.takeUnretainedValue()
}

// Preserve diagnostic callers while refusing selectors outside the getter ABI
func objectValue(_ object: AnyObject, _ name: String) -> AnyObject? {
  guard let getter = BridgeObjectGetter(rawValue: name) else { return nil }
  return objectValue(object, getter)
}

func objectValue(_ object: AnyObject, _ query: BridgeStringQuery, _ value: NSString) -> AnyObject? {
  let selector = NSSelectorFromString(query.rawValue)
  guard let implementation = implementation(object, selector, query.contractName) else {
    return nil
  }
  typealias Call = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation, to: Call.self)(object, selector, value)?
    .takeUnretainedValue()
}

func aliasValue(_ manager: AnyObject, _ alias: NSString, _ value: NSString) -> AnyObject? {
  let selector = NSSelectorFromString("getAssetSetUsagesForUsageAlias:usageAliasValue:")
  guard let implementation = implementation(manager, selector, .configurationManager)
  else { return nil }
  typealias Call = @convention(c) (AnyObject, Selector, NSString, NSString) -> Unmanaged<AnyObject>?
  return unsafeBitCast(implementation, to: Call.self)(
    manager, selector, alias, value)?.takeUnretainedValue()
}

func initializeSubscription(
  _ type: AnyClass, _ name: NSString, _ sets: NSDictionary, _ aliases: NSDictionary
) -> AnyObject? {
  let allocate = NSSelectorFromString("alloc")
  guard let allocateImplementation = implementation(type, allocate, .allocation) else {
    return nil
  }
  typealias Allocate = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
  guard
    let allocated = unsafeBitCast(allocateImplementation, to: Allocate.self)(type, allocate)
  else { return nil }
  let selector = NSSelectorFromString("initWithName:assetSets:usageAliases:")
  typealias Initialize =
    @convention(c) (AnyObject, Selector, NSString, NSDictionary, NSDictionary) -> Unmanaged<
      AnyObject
    >?
  // init consumes alloc's ownership, including nil and replacement-object
  // returns
  let object = allocated.takeUnretainedValue()
  // alloc may return a different class; check the receiver before calling its
  // IMP
  guard let initialize = implementation(object, selector, .subscription) else {
    allocated.release()
    return nil
  }
  return unsafeBitCast(initialize, to: Initialize.self)(
    object, selector, name, sets, aliases)?.takeRetainedValue()
}

func validateSubscription(_ object: AnyObject, _ manager: AnyObject, _ error: inout AnyObject?)
  -> Bool
{
  let selector = NSSelectorFromString("isValid:error:")
  guard let implementation = implementation(object, selector, .subscription) else {
    error = NSError(
      domain: "org.pared", code: 69,
      userInfo: [NSLocalizedDescriptionKey: "Subscription validation ABI changed"])
    return false
  }
  typealias Call =
    @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<AnyObject?>)
    -> ObjCBool
  return unsafeBitCast(implementation, to: Call.self)(
    object, selector, manager, &error
  ).boolValue
}

func latestStatus(_ type: AnyClass, _ name: NSString, _ error: inout AnyObject?) -> AnyObject? {
  let selector = NSSelectorFromString("latestStatusForClients:error:")
  guard let implementation = implementation(type, selector, .autoAssetManager) else {
    error = NSError(
      domain: "org.pared", code: 69,
      userInfo: [NSLocalizedDescriptionKey: "Local status ABI changed"])
    return nil
  }
  typealias Call =
    @convention(c) (AnyObject, Selector, NSString, AutoreleasingUnsafeMutablePointer<AnyObject?>) ->
    Unmanaged<AnyObject>?
  return unsafeBitCast(implementation, to: Call.self)(type, selector, name, &error)?
    .takeUnretainedValue()
}

func scalarBool(_ object: AnyObject, _ getter: BridgeBoolGetter) -> Bool? {
  let selector = NSSelectorFromString(getter.rawValue)
  guard let implementation = implementation(object, selector, getter.contractName) else {
    return nil
  }
  typealias Call = @convention(c) (AnyObject, Selector) -> ObjCBool
  return unsafeBitCast(implementation, to: Call.self)(object, selector).boolValue
}

func scalarInt64(_ object: AnyObject, _ getter: BridgeInt64Getter) -> Int64? {
  let selector = NSSelectorFromString(getter.rawValue)
  guard let implementation = implementation(object, selector, .assetSetStatusScalars)
  else {
    return nil
  }
  typealias Call = @convention(c) (AnyObject, Selector) -> Int64
  return unsafeBitCast(implementation, to: Call.self)(object, selector)
}

enum BridgeForwardedMethod {
  case operation, diagnostic

  var selector: Selector {
    NSSelectorFromString(
      self == .operation ? "operationWithConfig:completion:" : "diagnosticInformation:")
  }

  var serviceContract: BridgeContract {
    self == .operation
      ? .operationService : .diagnosticService
  }

  var receiverContract: BridgeContract {
    self == .operation ? .operationReceiver : .diagnosticReceiver
  }
}

// Foundation's generated XPC proxy methods erase block and oneway encodings
// Validate the full forwarding signature used to construct the invocation
func bridgeMessageDispatcher(_ object: NSObject, _ method: BridgeForwardedMethod)
  -> UnsafeMutableRawPointer?
{
  let selector = method.selector
  let query = NSSelectorFromString("methodSignatureForSelector:")
  guard let implementation = implementation(object, query, .messageSignature),
    let signatureClass = NSClassFromString("NSMethodSignature")
  else { return nil }
  typealias Signature = @convention(c) (AnyObject, Selector, Selector) -> Unmanaged<AnyObject>?
  guard
    let actual = unsafeBitCast(implementation, to: Signature.self)(object, query, selector)?
      .takeUnretainedValue() as? NSObject,
    actual.isKind(of: signatureClass),
    [method.serviceContract, method.receiverContract].contains(where: {
      let expected = protocol_getMethodDescription(contract($0), selector, true, true)
      return methodSignature(expected.types).map { actual.isEqual($0) } == true
    })
  else { return nil }
  return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
}

func sendConfiguration(
  _ proxy: NSObject?, _ configuration: BridgeConfiguration, _ completion: BridgeCompletion?,
  _ error: BridgeError
) -> Bool {
  guard let proxy, let completion else {
    bridgeSetError(error, "A request requires a proxy and completion; no request sent")
    return false
  }
  guard let dispatcher = bridgeMessageDispatcher(proxy, .operation) else {
    bridgeSetError(error, "The operation receiver ABI is unavailable; no request sent")
    return false
  }
  typealias Send = @convention(c) (AnyObject, Selector, NSDictionary, BridgeCompletion) -> Void
  let send = unsafeBitCast(dispatcher, to: Send.self)
  send(
    proxy, NSSelectorFromString("operationWithConfig:completion:"), configuration.dictionary,
    completion)
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
  guard let values = values as? [NSString: NSString] else { return nil }
  return NSDictionary(dictionary: values, copyItems: true)
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
