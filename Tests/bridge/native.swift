// Compiled with the production bridge to exercise private guards directly
import Darwin
import Foundation
import ObjectiveC
import Synchronization

private let checks = Mutex(0)
private func check(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
  checks.withLock { $0 += 1 }
  precondition(condition, "Check failed", file: file, line: line)
}

private struct AcceptedConnection: @unchecked Sendable {
  let connection: NSXPCConnection
}

// Apple's protocol includes oneway, which Swift cannot declare
private final class Capture: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  var configuration: NSDictionary?
  var replyError: NSError?
  let connections = Mutex<[AcceptedConnection]>([])
  var received: DispatchSemaphore?
  var dropReplies = false

  @objc(operationWithConfig:completion:)
  func operation(_ configuration: NSDictionary, completion: @escaping BridgeCompletion) {
    self.configuration = configuration
    received?.signal()
    if !dropReplies { completion(replyError) }
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.exportedInterface = paredServiceInterface()
    connection.exportedObject = self
    connections.withLock { $0.append(AcceptedConnection(connection: connection)) }
    connection.resume()
    return true
  }

  func invalidate() {
    connections.withLock { values in
      for value in values { value.connection.invalidate() }
    }
  }
}

@objcMembers private final class FakeSelector: NSObject {
  var assetType: AnyObject? = "type" as NSString
  var assetSpecifier: AnyObject? = "specifier" as NSString
  var assetVersion: AnyObject? = "version" as NSString
}
@objcMembers private final class FakeEntry: NSObject {
  var assetID: AnyObject? = "id" as NSString
  var fullAssetSelector: AnyObject?
}
@objcMembers private class FakeStatus: NSObject {
  var latestDownloadedAtomicInstance: AnyObject?
  var configuredAssetEntries: AnyObject? = NSArray()
  var latestDowloadedAtomicInstanceEntries: AnyObject? = NSArray()
  var downloadedNetworkBytes = Int64.max
  var downloadedFilesystemBytes = Int64.min
  var vendingAtomicInstanceForConfiguredEntries = true
}
private final class WrongScalar: NSObject {
  @objc func downloadedNetworkBytes() -> AnyObject { fatalError("Unsafe scalar getter called") }
}
@objcMembers private final class FakeSet: NSObject {
  var autoAssetType: AnyObject? = "type" as NSString
  var usageTypes: AnyObject? = ["usage"] as NSArray
  var usageValues: AnyObject?
}
@objcMembers private final class FakeManager: NSObject {
  var set: AnyObject?
  var alias: AnyObject? = ["set": ["usage": "ENABLED"]] as NSDictionary
  func getAssetSet(_ name: NSString) -> AnyObject? { set }
  @objc(getAssetSetUsagesForUsageAlias:usageAliasValue:)
  func resolve(_ alias: NSString, value: NSString) -> AnyObject? { self.alias }
}

private func subscription(_ recovery: NSDictionary) -> ParedAssetSubscription {
  var error: NSError?
  let result = bridgeSubscription(
    recovery["name"] as AnyObject?, recovery["assetSetUsages"] as AnyObject? ?? NSDictionary(),
    recovery["usageAliases"] as AnyObject?, &error)
  check(result != nil && error == nil)
  return result!
}

private func malformedInputs(_ recovery: NSDictionary) {
  let capture = Capture()
  let valid = subscription(recovery)
  let completion: BridgeCompletion = { _ in fatalError("Invalid request completed") }
  let invalid: [AnyObject] = [
    NSNull(), NSNumber(value: 42), "" as NSString, NSArray(), NSDictionary(), NSObject(),
    [""] as NSArray, [42] as NSArray, ["set": NSNull()] as NSDictionary,
    [42: ["usage": "ENABLED"]] as NSDictionary, ["set": ["usage": 42]] as NSDictionary,
    ["set": ["usage": "DISABLED"]] as NSDictionary,
  ]
  for value in invalid {
    var error: NSError?
    check(bridgeSubscription(value, NSDictionary(), NSDictionary(), &error) == nil && error != nil)
    error = nil
    check(
      bridgeSubscription("invalid" as NSString, value, NSDictionary(), &error) == nil
        && error != nil)
    error = nil
    check(
      bridgeSubscription("invalid" as NSString, NSDictionary(), value, &error) == nil
        && error != nil)
    error = nil
    check(!bridgePerformReset(capture, value, completion, &error) && error != nil)
    error = nil
    check(
      !bridgePerformSubscribe(capture, value, [valid] as NSArray, completion, &error)
        && error != nil)
    error = nil
    check(
      !bridgePerformSubscribe(capture, "test" as NSString, value, completion, &error)
        && error != nil)
    error = nil
    check(
      !bridgePerformUnsubscribe(capture, "test" as NSString, value, completion, &error)
        && error != nil)
    error = nil
    check(bridgeLocalStatus(value, &error) == nil && error != nil)
    // Typed configuration entry points reject non-string objects at their guard
    check(bridgeAssetTypeForSet(value as? NSString) == nil)
    check(bridgeUsageTypesForSet(value as? NSString) == nil)
    check(bridgeResolveUsageAlias(value, "missing" as NSString) == nil)
    check(capture.configuration == nil)
  }
  var error: NSError?
  check(
    !bridgePerformSubscribe(
      capture, "test" as NSString, [valid, valid] as NSArray, completion, &error) && error != nil)
  check(
    !bridgePerformSubscribe(
      capture, "test" as NSString, [NSObject()] as NSArray, completion, &error))
  check(!bridgePerformReset(nil, ["test"] as NSArray, completion, &error))
  check(!bridgePerformReset(capture, ["test"] as NSArray, nil, &error))
  check(!bridgePerformSubscribe(nil, "test" as NSString, [valid] as NSArray, completion, &error))
  check(!bridgePerformSubscribe(capture, "test" as NSString, [valid] as NSArray, nil, &error))
  check(!bridgePerformUnsubscribe(nil, "test" as NSString, ["test"] as NSArray, completion, &error))
  check(!bridgePerformUnsubscribe(capture, "test" as NSString, ["test"] as NSArray, nil, &error))
  check(capture.configuration == nil)
}

private func ownership(_ recovery: NSDictionary) throws {
  let name = NSMutableString(string: recovery["name"] as! String)
  let aliases = NSMutableDictionary()
  for (key, value) in recovery["usageAliases"] as! NSDictionary {
    aliases[key as! NSString] = NSMutableString(string: value as! String)
  }
  let sets = NSMutableDictionary()
  for (key, value) in recovery["assetSetUsages"] as? NSDictionary ?? NSDictionary() {
    let usages = NSMutableDictionary()
    for (usage, enabled) in value as! NSDictionary {
      usages[usage as! NSString] = NSMutableString(string: enabled as! String)
    }
    sets[key as! NSString] = usages
  }
  var error: NSError?
  let object = bridgeSubscription(name, sets, aliases, &error)
  check(object != nil && error == nil)
  let native = object!.native
  let before = try NSKeyedArchiver.archivedData(withRootObject: native, requiringSecureCoding: true)
  name.setString("changed")
  for value in aliases.allValues { (value as! NSMutableString).setString("changed") }
  for value in sets.allValues {
    let usages = value as! NSMutableDictionary
    for enabled in usages.allValues { (enabled as! NSMutableString).setString("DISABLED") }
    usages.removeAllObjects()
  }
  aliases.removeAllObjects()
  sets.removeAllObjects()
  let after = try NSKeyedArchiver.archivedData(withRootObject: native, requiringSecureCoding: true)
  check(before == after)
  check((objectValue(native, "name") as? NSString)?.isEqual(recovery["name"]) == true)
  let capture = Capture()
  let subscriber = NSMutableString(string: "subscriber")
  let target = NSMutableString(string: "target")
  let names = NSMutableArray(array: [target, target])
  check(bridgePerformUnsubscribe(capture, subscriber, names, { check($0 == nil) }, &error))
  subscriber.setString("changed")
  target.setString("changed")
  names.removeAllObjects()
  check(capture.configuration?["Subscriber"] as? String == "subscriber")
  check(capture.configuration?["Subscriptions"] as? [String] == ["target"])
}

private func wire(_ recoveries: [NSDictionary]) {
  let server = Capture()
  let listener = NSXPCListener.anonymous()
  listener.delegate = server
  listener.resume()
  let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
  connection.remoteObjectInterface = paredServiceInterface()
  check(connection.remoteObjectInterface != nil)
  connection.resume()
  defer {
    connection.invalidate()
    listener.invalidate()
    server.invalidate()
  }
  let proxy =
    connection.remoteObjectProxyWithErrorHandler { error in
      fatalError("Unexpected XPC transport error: \(error)")
    } as! NSObject
  let subscriptions = recoveries.map(subscription)
  for index in 0..<90 {
    autoreleasepool {
      server.replyError =
        index % 2 == 0
        ? nil
        : NSError(
          domain: "test.daemon", code: 7,
          userInfo: ["nested": NSError(domain: "test.underlying", code: 8)])
      let done = DispatchSemaphore(value: 0)
      let completion: BridgeCompletion = { reply in
        check((reply?.domain == "test.daemon") == (index % 2 != 0))
        if let reply {
          check(reply.code == 7)
          check((reply.userInfo["nested"] as? NSError)?.code == 8)
        }
        done.signal()
      }
      var error: NSError?
      switch index % 3 {
      case 0:
        check(
          bridgePerformSubscribe(
            proxy, "test" as NSString, subscriptions as NSArray, completion, &error))
      case 1:
        check(
          bridgePerformUnsubscribe(
            proxy, "test" as NSString, ["a", "a", "b"] as NSArray, completion, &error))
      default: check(bridgePerformReset(proxy, ["b", "a", "a"] as NSArray, completion, &error))
      }
      check(error == nil)
      check(done.wait(timeout: .now() + 5) == .success)
      let request = server.configuration!
      check(request["SubscriptionUser"] == nil)
      if index % 3 == 0 {
        let decoded = request["Subscriptions"] as! [NSObject]
        check(decoded.count == subscriptions.count)
        for (offset, object) in decoded.enumerated() {
          check(object.isKind(of: NSClassFromString("UAFAssetSetSubscription")!))
          check(object.isEqual(subscriptions[offset].native))
        }
        check(request["UserInitiated"] as? Bool == true)
      } else {
        check(request[index % 3 == 1 ? "Subscriptions" : "AssetSets"] as? [String] == ["a", "b"])
      }
    }
  }
}

private func wireFailure() {
  let server = Capture()
  server.dropReplies = true
  server.received = DispatchSemaphore(value: 0)
  let listener = NSXPCListener.anonymous()
  listener.delegate = server
  listener.resume()
  let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
  connection.remoteObjectInterface = paredServiceInterface()
  connection.resume()
  defer {
    connection.invalidate()
    listener.invalidate()
    server.invalidate()
  }
  let disconnected = DispatchSemaphore(value: 0)
  let transportError = Mutex<NSError?>(nil)
  let proxy =
    connection.remoteObjectProxyWithErrorHandler { error in
      transportError.withLock { $0 = error as NSError }
      disconnected.signal()
    } as! NSObject
  var error: NSError?
  check(
    bridgePerformReset(
      proxy, ["isolated.test"] as NSArray, { _ in fatalError("Missing reply completed") }, &error))
  check(error == nil)
  check(server.received!.wait(timeout: .now() + 5) == .success)
  check(disconnected.wait(timeout: .now()) == .timedOut)
  server.invalidate()
  check(disconnected.wait(timeout: .now() + 5) == .success)
  check(transportError.withLock { $0 != nil })
  print("XPC failure: missing reply and interrupted connection observed")
}

// Restore every injected implementation before another check observes it
private func replacing(_ method: Method, block: Any, body: () -> Void) {
  let replacement = imp_implementationWithBlock(block)
  let original = method_setImplementation(method, replacement)
  defer {
    method_setImplementation(method, original)
    imp_removeBlock(replacement)
  }
  body()
}

private func statusFaults() {
  let method = class_getClassMethod(
    NSClassFromString("UAFAutoAssetManager"), NSSelectorFromString("latestStatusForClients:error:"))!
  var returned: AnyObject?
  var returnedError: AnyObject?
  let block:
    @convention(block) (AnyObject, NSString, AutoreleasingUnsafeMutablePointer<AnyObject?>) ->
      AnyObject? = { _, _, error in
        error.pointee = returnedError
        return returned
      }
  replacing(method, block: block) {
    var error: NSError?
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
    returned = NSObject()
    error = nil
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
    let status = FakeStatus()
    returned = status
    error = nil
    var snapshot = bridgeLocalStatus("test" as NSString, &error)
    check(
      snapshot != nil && error == nil && snapshot!.downloadedNetworkBytes == Int64.max
        && snapshot!.downloadedFilesystemBytes == Int64.min
        && snapshot!.vendingAtomicInstanceForConfiguredEntries)
    returnedError = NSError(domain: "test.release", code: 1)
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error === returnedError)
    returnedError = NSNull()
    error = nil
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
    returnedError = nil
    status.configuredAssetEntries = [NSObject()] as NSArray
    error = nil
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
    status.configuredAssetEntries = NSArray()
    let entry = FakeEntry()
    let selector = FakeSelector()
    entry.fullAssetSelector = selector
    entry.assetID = NSMutableString(string: "id")
    selector.assetType = NSMutableString(string: "type")
    status.latestDownloadedAtomicInstance = NSMutableString(string: "instance")
    status.latestDowloadedAtomicInstanceEntries = [entry] as NSArray
    error = nil
    snapshot = bridgeLocalStatus("test" as NSString, &error)
    check(snapshot != nil && error == nil && snapshot!.downloadedAssets.count == 1)
    (entry.assetID as! NSMutableString).setString("changed")
    (selector.assetType as! NSMutableString).setString("changed")
    (status.latestDownloadedAtomicInstance as! NSMutableString).setString("changed")
    check(
      snapshot!.downloadedAssets[0].assetID == "id"
        && snapshot!.downloadedAssets[0].assetType == "type"
        && snapshot!.latestDownloadedAtomicInstance == "instance")
    for value: AnyObject in [NSNull(), NSNumber(value: 42), "" as NSString, NSObject()] {
      selector.assetVersion = value
      error = nil
      check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
    }
    selector.assetVersion = "version" as NSString
    entry.fullAssetSelector = NSObject()
    check(bridgeLocalStatus("test" as NSString, &error) == nil)
    status.latestDowloadedAtomicInstanceEntries = [NSObject()] as NSArray
    check(bridgeLocalStatus("test" as NSString, &error) == nil)
    entry.fullAssetSelector = selector
    status.latestDowloadedAtomicInstanceEntries = [entry] as NSArray
    let scalar = NSSelectorFromString("downloadedNetworkBytes")
    let wrong = class_getInstanceMethod(WrongScalar.self, scalar)!
    let drifted: AnyClass = objc_allocateClassPair(FakeStatus.self, "ParedDriftedStatus", 0)!
    check(
      class_addMethod(
        drifted, scalar, method_getImplementation(wrong), method_getTypeEncoding(wrong)))
    objc_registerClassPair(drifted)
    object_setClass(status, drifted)
    defer { object_setClass(status, FakeStatus.self) }
    error = nil
    check(bridgeLocalStatus("test" as NSString, &error) == nil && error != nil)
  }
}

private func validationErrorFaults(_ recovery: NSDictionary) {
  let method = class_getInstanceMethod(
    NSClassFromString("UAFAssetSetSubscription"), NSSelectorFromString("isValid:error:"))!
  var returnedError: AnyObject?
  var valid = true
  let block:
    @convention(block) (AnyObject, AnyObject, AutoreleasingUnsafeMutablePointer<AnyObject?>) -> Bool =
      { _, _, error in
        error.pointee = returnedError
        return valid
      }
  replacing(method, block: block) {
    func rejected() -> NSError {
      var error: NSError?
      check(
        bridgeSubscription(
          recovery["name"] as AnyObject?,
          recovery["assetSetUsages"] as AnyObject? ?? NSDictionary(),
          recovery["usageAliases"] as AnyObject?, &error) == nil && error != nil)
      return error!
    }
    for value: AnyObject in [NSNull(), "wrong" as NSString, NSNumber(value: 42), NSDictionary()] {
      returnedError = value
      _ = rejected()
    }
    returnedError = nil
    valid = false
    _ = rejected()
    returnedError = NSError(domain: "test.validation", code: 1)
    check(rejected() === returnedError)
  }
}

private func configurationFaults() {
  let method = class_getClassMethod(
    NSClassFromString("UAFConfigurationManager"), NSSelectorFromString("defaultManager"))!
  let manager = FakeManager()
  let set = FakeSet()
  manager.set = set
  let block: @convention(block) (AnyObject) -> AnyObject? = { _ in manager }
  replacing(method, block: block) {
    func request(aliases: Bool = false, accepted: Bool) {
      var error: NSError?
      let result = bridgeSubscription(
        "test" as NSString, aliases ? NSDictionary() : manager.alias,
        aliases ? ["alias": "value"] as NSDictionary : NSDictionary(), &error)
      check((result != nil) == accepted && (error == nil) == accepted)
    }
    request(accepted: true)
    request(aliases: true, accepted: true)
    set.usageValues = ["usage": ["DISABLED"]] as NSDictionary
    request(accepted: false)
    request(aliases: true, accepted: false)
    set.usageValues = ["usage": ["ENABLED"]] as NSDictionary
    request(accepted: true)
    set.usageTypes = NSNull()
    request(accepted: false)
    check(bridgeUsageTypesForSet("set" as NSString) == nil)
    set.usageTypes = ["usage"] as NSArray
    for restriction: AnyObject in [
      NSNull(), NSNumber(value: 42), "ENABLED" as NSString, NSArray(), [42] as NSArray,
    ] {
      set.usageValues = ["usage": restriction] as NSDictionary
      request(accepted: false)
    }
    set.usageValues = nil
    for expansion: AnyObject in [
      NSNull(), NSNumber(value: 42), NSArray(), NSDictionary(),
      ["set": NSNull()] as NSDictionary, ["set": ["usage": "DISABLED"]] as NSDictionary,
      ["set": ["missing": "ENABLED"]] as NSDictionary,
    ] {
      manager.alias = expansion
      request(aliases: true, accepted: false)
    }
  }
}

private func interfaceFaults() {
  let method = class_getClassMethod(
    NSClassFromString("UAFXPCProxyServiceInterface"), NSSelectorFromString("defaultInterface"))!
  var returned: AnyObject? = NSObject()
  let block: @convention(block) (AnyObject) -> AnyObject? = { _ in returned }
  replacing(method, block: block) {
    check(paredServiceInterface() == nil)
    returned = nil
    check(paredServiceInterface() == nil)
    let declaration = NSProtocolFromString("UAFXPCProxyService")!
    let selector = NSSelectorFromString("operationWithConfig:completion:")
    let request = NSSet(
      array: [
        NSDictionary.self, NSString.self, NSArray.self, NSNumber.self,
        NSClassFromString("UAFAssetSetSubscription")!,
      ] as [AnyClass])
    for omitted in request {
      let classes = request.mutableCopy() as! NSMutableSet
      classes.remove(omitted)
      let interface = NSXPCInterface(with: declaration)
      interface.setClasses(
        classes as! Set<AnyHashable>, for: selector, argumentIndex: 0, ofReply: false)
      interface.setClasses(
        NSSet(object: NSError.self) as! Set<AnyHashable>, for: selector, argumentIndex: 0,
        ofReply: true)
      returned = interface
      check(paredServiceInterface() == nil)
    }
    let interface = NSXPCInterface(with: declaration)
    interface.setClasses(
      request as! Set<AnyHashable>, for: selector, argumentIndex: 0, ofReply: false)
    interface.setClasses(
      NSSet(object: NSString.self) as! Set<AnyHashable>, for: selector, argumentIndex: 0,
      ofReply: true)
    returned = interface
    check(paredServiceInterface() == nil)
    interface.setClasses(
      NSSet(object: NSError.self) as! Set<AnyHashable>, for: selector, argumentIndex: 0,
      ofReply: true)
    check(paredServiceInterface() === interface)
  }
}

private func abiFaults() {
  func matches(_ actual: String?, _ expected: String?) -> Bool {
    if let actual {
      return actual.withCString { lhs in
        guard let expected else { return bridgeSignatureMatches(lhs, nil) }
        return expected.withCString { bridgeSignatureMatches(lhs, $0) }
      }
    }
    guard let expected else { return bridgeSignatureMatches(nil, nil) }
    return expected.withCString { bridgeSignatureMatches(nil, $0) }
  }
  check(matches("Vv32@0:8@16@?24", "Vv64@0:16@32@?48"))
  check(!matches("v32@0:8@16@?24", "Vv32@0:8@16@?24"))
  check(!matches("Vv32@0:8@16@24", "Vv32@0:8@16@?24"))
  check(!matches("q16@0:8", "Q16@0:8"))
  check(!matches("@16@0:8", "q16@0:8"))
  check(!matches("B32@0:8@16^v24", "B32@0:8@16^@24"))
  check(!matches(nil, "@16@0:8"))
  check(!matches("@16@0:8", nil))
  #if arch(x86_64)
    let boolean = "c"
  #else
    let boolean = "B"
  #endif
  // Independent expected encodings prevent production contracts testing themselves
  let cases: [(String, String, Bool, String, String)] = [
    ("UAFConfigurationManager", "defaultManager", true, "ParedConfigurationManagerAPI", "@@:"),
    ("UAFConfigurationManager", "getAssetSet:", false, "ParedConfigurationManagerAPI", "@@:@"),
    (
      "UAFConfigurationManager", "getAssetSetUsagesForUsageAlias:usageAliasValue:", false,
      "ParedConfigurationManagerAPI", "@@:@@"
    ),
    ("UAFAssetSetConfiguration", "autoAssetType", false, "ParedAssetSetConfigurationAPI", "@@:"),
    ("UAFAssetSetConfiguration", "usageTypes", false, "ParedAssetSetUsageAPI", "@@:"),
    ("UAFAssetSetConfiguration", "usageValues", false, "ParedAssetSetUsageAPI", "@@:"),
    (
      "UAFAssetSetSubscription", "initWithName:assetSets:usageAliases:", false,
      "ParedSubscriptionAPI", "@@:@@@"
    ),
    ("UAFAssetSetSubscription", "isValid:error:", false, "ParedSubscriptionAPI", "\(boolean)@:@^@"),
    ("UAFAssetSetSubscription", "supportsSecureCoding", true, "NSSecureCoding", "\(boolean)@:"),
    ("UAFAssetSetSubscription", "encodeWithCoder:", false, "NSCoding", "v@:@"),
    ("UAFAssetSetSubscription", "initWithCoder:", false, "NSCoding", "@@:@"),
    ("UAFXPCProxyServiceInterface", "defaultInterface", true, "ParedServiceInterfaceAPI", "@@:"),
    (
      "UAFAutoAssetManager", "latestStatusForClients:error:", true, "ParedAutoAssetManagerAPI",
      "@@:@^@"
    ),
    (
      "MAAutoAssetSetStatus", "latestDownloadedAtomicInstance", false,
      "ParedAssetSetStatusObjectsAPI", "@@:"
    ),
    (
      "MAAutoAssetSetStatus", "configuredAssetEntries", false, "ParedAssetSetStatusObjectsAPI",
      "@@:"
    ),
    (
      "MAAutoAssetSetStatus", "latestDowloadedAtomicInstanceEntries", false,
      "ParedAssetSetStatusObjectsAPI", "@@:"
    ),
    (
      "MAAutoAssetSetStatus", "downloadedNetworkBytes", false, "ParedAssetSetStatusScalarsAPI",
      "q@:"
    ),
    (
      "MAAutoAssetSetStatus", "downloadedFilesystemBytes", false, "ParedAssetSetStatusScalarsAPI",
      "q@:"
    ),
    (
      "MAAutoAssetSetStatus", "vendingAtomicInstanceForConfiguredEntries", false,
      "ParedAssetSetStatusScalarsAPI", "\(boolean)@:"
    ),
    ("MAAutoAssetSetAtomicEntry", "assetID", false, "ParedDownloadedEntryAPI", "@@:"),
    ("MAAutoAssetSetAtomicEntry", "fullAssetSelector", false, "ParedDownloadedEntryAPI", "@@:"),
    ("MAAutoAssetSelector", "assetType", false, "ParedAutoAssetSelectorAPI", "@@:"),
    ("MAAutoAssetSelector", "assetSpecifier", false, "ParedAutoAssetSelectorAPI", "@@:"),
    ("MAAutoAssetSelector", "assetVersion", false, "ParedAutoAssetSelectorAPI", "@@:"),
    ("UAFXPCService", "operationWithConfig:completion:", false, "ParedServiceAPI", "Vv@:@@?"),
  ]
  for (index, entry) in cases.enumerated() {
    let (name, methodName, meta, contractName, encoding) = entry
    let type: AnyClass = NSClassFromString(name)!
    let selector = NSSelectorFromString(methodName)
    let method =
      (meta ? class_getClassMethod(type, selector) : class_getInstanceMethod(type, selector))!
    check(encoding.withCString { bridgeSignatureMatches(method_getTypeEncoding(method), $0) })
    check(bridgeMethodMatches(method, selector, contract(contractName), !meta))
    let fault: AnyClass = objc_allocateClassPair(NSObject.self, "ParedABIFault\(index)", 0)!
    let receiver: AnyClass = meta ? object_getClass(fault)! : fault
    check(class_addMethod(receiver, selector, method_getImplementation(method), "v16@0:8"))
    objc_registerClassPair(fault)
    check(
      !bridgeMethodMatches(
        class_getInstanceMethod(receiver, selector), selector, contract(contractName), !meta))
  }
  print("Live encodings checked and drift rejected: \(cases.count) selectors")
}

private func openFiles() -> Int {
  (0..<getdtablesize()).reduce(0) { $0 + (fcntl($1, F_GETFD) == -1 ? 0 : 1) }
}

// Foundation snapshots are read-only while concurrent workers use them
private final class ReadFixtures: @unchecked Sendable {
  let types: NSDictionary
  let recoveries: [NSDictionary]
  let baseline: [String: NSObject]
  init(types: NSDictionary, recoveries: [NSDictionary], baseline: [String: NSObject]) {
    self.types = types
    self.recoveries = recoveries
    self.baseline = baseline
  }
}

private func concurrentReads(_ catalog: NSDictionary, _ recoveries: [NSDictionary]) {
  let types = (catalog["assetTypes"] as! NSDictionary).mutableCopy() as! NSMutableDictionary
  types.addEntries(from: catalog["recoveryAssetTypes"] as? [AnyHashable: Any] ?? [:])
  let sets = types.allKeys as! [String]
  var baseline: [String: NSObject] = [:]
  for set in sets {
    var error: NSError?
    let status = paredLocalStatus(set, &error)
    check((status != nil) != (error != nil))
    baseline[set] = status ?? error!
  }
  let fixtures = ReadFixtures(
    types: types.copy() as! NSDictionary, recoveries: recoveries, baseline: baseline)
  let before = openFiles()
  DispatchQueue.concurrentPerform(iterations: 240) { index in
    autoreleasepool {
      let set = sets[index % sets.count]
      check(paredAssetTypeForSet(set) == fixtures.types[set] as? String)
      check(paredUsageTypesForSet(set) != nil)
      check(paredServiceInterface() != nil)
      let recovery = fixtures.recoveries[index % fixtures.recoveries.count]
      let native = subscription(recovery).native
      do {
        let archive = try NSKeyedArchiver.archivedData(
          withRootObject: native, requiringSecureCoding: true)
        let decoded =
          try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSClassFromString("UAFAssetSetSubscription")!], from: archive) as? NSObject
        check(decoded?.isEqual(native) == true)
      } catch { fatalError("Secure coding failed: \(error)") }
      for (alias, value) in recovery["usageAliases"] as! NSDictionary {
        check((paredResolveUsageAlias(alias as! String, value as! String)?.count ?? 0) > 0)
      }
      var error: NSError?
      let status = paredLocalStatus(set, &error)
      check((status != nil) != (error != nil))
      if let prior = fixtures.baseline[set] as? NSError {
        check(error?.domain == prior.domain && error?.code == prior.code)
      } else {
        let expected = fixtures.baseline[set] as! ParedLocalDownloadStatus
        check(
          status != nil && status!.configuredAssetEntries == expected.configuredAssetEntries
            && status!.downloadedAssets.count == expected.downloadedAssets.count)
      }
    }
  }
  let after = openFiles()
  print("Live concurrent reads: 240, descriptors before/after: \(before)/\(after)")
  check(after == before)
}

@main private enum NativeChecks {
  static func main() throws {
    try autoreleasepool {
      check(CommandLine.arguments.count == 2)
      check(
        dlopen(
          "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework",
          RTLD_NOW) != nil)
      let catalog =
        try JSONSerialization.jsonObject(
          with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! NSDictionary
      let recoveries = (catalog["features"] as! NSDictionary).allValues.compactMap {
        ($0 as? NSDictionary)?["recovery"] as? NSDictionary
      }
      check(!recoveries.isEmpty)
      malformedInputs(recoveries[0])
      for recovery in recoveries { try ownership(recovery) }
      wire(recoveries)
      wireFailure()
      statusFaults()
      validationErrorFaults(recoveries[0])
      configurationFaults()
      interfaceFaults()
      abiFaults()
      concurrentReads(catalog, recoveries)
      print("Private API checks passed: \(checks.withLock { $0 })")
    }
  }
}
