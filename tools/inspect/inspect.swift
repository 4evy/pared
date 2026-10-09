// Read configuration and status and check subscription serialization locally
// No subscription or reset operations are sent. Status reads briefly lock
// assets
// Run tools/inspect/inspect.sh Sources/Pared/Resources/catalog.json
// Add --published-catalog TYPE to decode published metadata without saving it
// Exit 0 means collection succeeded; inspect per-set and archive errors
import Darwin
import Foundation
import ObjectiveC

private func errorDetails(_ error: NSError?) -> [String: Any] {
  guard let error else { return [:] }
  return ["domain": error.domain, "code": error.code, "description": error.localizedDescription]
}

private func classMethods(_ name: String, inspect: (Method) -> Any?) -> [String: Any] {
  let type: AnyClass? = NSClassFromString(name)
  let values = [false, true].flatMap { meta -> [(String, Any)] in
    var count: UInt32 = 0
    guard let entries = class_copyMethodList(meta ? object_getClass(type) : type, &count) else {
      return []
    }
    defer { free(entries) }
    return UnsafeBufferPointer(start: entries, count: Int(count)).compactMap { method in
      guard let value = inspect(method) else { return nil }
      return ((meta ? "+" : "-") + NSStringFromSelector(method_getName(method)), value)
    }
  }
  return Dictionary(values, uniquingKeysWith: { _, latest in latest })
}

private func methods(_ name: String) -> [String: Any] {
  classMethods(name) { method in
    method_getTypeEncoding(method).map { String(cString: $0) }
  }
}

// Remove the image slide so implementation addresses stay useful across runs
private func implementations(_ name: String) -> [String: Any] {
  classMethods(name) { method in
    let implementation = unsafeBitCast(method_getImplementation(method), to: UnsafeRawPointer.self)
    var info = Dl_info()
    guard dladdr(implementation, &info) != 0, let path = info.dli_fname,
      let image = (0..<_dyld_image_count()).first(where: {
        strcmp(_dyld_get_image_name($0), path) == 0
      })
    else { return nil }
    let address =
      UInt(bitPattern: implementation) &- UInt(bitPattern: _dyld_get_image_vmaddr_slide(image))
    return [
      "image": String(cString: path), "address": String(format: "0x%llx", UInt64(address)),
    ]
  }
}

private func properties(_ name: String) -> [String: Any] {
  var count: UInt32 = 0
  guard let entries = class_copyPropertyList(NSClassFromString(name), &count) else { return [:] }
  defer { free(entries) }
  let values = UnsafeBufferPointer(start: entries, count: Int(count)).compactMap { property in
    property_getAttributes(property).map {
      (String(cString: property_getName(property)), String(cString: $0))
    }
  }
  return Dictionary(values, uniquingKeysWith: { _, latest in latest })
}

private func frameworkImages() -> [String: Any] {
  var result: [String: Any] = [:]
  for image in 0..<_dyld_image_count() {
    guard let pathPointer = _dyld_get_image_name(image), let header = _dyld_get_image_header(image),
      header.pointee.magic == MH_MAGIC_64
    else { continue }
    let path = String(cString: pathPointer)
    guard
      path.contains("/UnifiedAssetFramework.framework/") || path.contains("/MobileAsset.framework/")
        || path.contains("/MobileAssetDaemon.framework/")
        || path.hasSuffix("/libMobileGestalt.dylib")
    else { continue }
    var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
    for _ in 0..<header.pointee.ncmds {
      let load = command.load(as: load_command.self)
      if load.cmd == LC_UUID {
        let uuid = command.load(as: uuid_command.self).uuid
        result[path] = UUID(uuid: uuid).uuidString
        break
      }
      command = command.advanced(by: Int(load.cmdsize))
    }
  }
  return result
}

private func classNames(_ classes: Set<AnyHashable>) -> [String] {
  classes.compactMap { ($0.base as? AnyClass).map(NSStringFromClass) }.sorted()
}

private func snapshot(_ status: ParedLocalDownloadStatus) -> [String: Any] {
  [
    "latestDownloadedAtomicInstance": status.latestDownloadedAtomicInstance as Any? ?? NSNull(),
    "configuredAssetEntries": status.configuredAssetEntries,
    "latestDowloadedAtomicInstanceEntries": status.latestDowloadedAtomicInstanceEntries,
    "downloadedNetworkBytes": status.downloadedNetworkBytes,
    "downloadedFilesystemBytes": status.downloadedFilesystemBytes,
    "vendingAtomicInstanceForConfiguredEntries": status.vendingAtomicInstanceForConfiguredEntries,
    "downloadedAssets": status.downloadedAssets.map {
      [
        "assetID": $0.assetID, "assetType": $0.assetType, "assetSpecifier": $0.assetSpecifier,
        "assetVersion": $0.assetVersion,
      ]
    },
  ]
}

private struct Inspection: OptionSet {
  let rawValue: Int
  static let methods = Self(rawValue: 1)
  static let implementations = Self(rawValue: 2)
  static let properties = Self(rawValue: 4)
  static let all: Self = [.methods, .implementations, .properties]
}

private let inspectedClasses: [(String, Inspection)] = [
  ("UAFConfigurationManager", [.methods, .implementations]),
  ("UAFAssetSetConfiguration", .all), ("UAFAssetConfiguration", [.methods, .implementations]),
  ("UAFAssetExpansion", [.methods, .implementations]),
  ("UAFCommonUtilities", [.methods, .implementations]),
  ("UAFAssetSetSubscription", .all), ("UAFXPCProxyServiceInterface", [.methods, .implementations]),
  ("UAFXPCService", .implementations), ("UAFAssetSetManager", .implementations),
  ("UAFSubscriptionStoreManager", .implementations), ("UAFUserManager", .implementations),
  ("UAFAutoAssetManager", [.methods, .implementations]), ("MAAutoAssetSet", .implementations),
  ("MAAutoAssetSetStatus", .all), ("MAAutoAssetSetAtomicEntry", .all),
  ("MAAutoAssetSetEntry", [.implementations, .properties]), ("MAAutoAssetSelector", .all),
  ("DownloadManager", [.methods, .implementations]), ("MAPallasConfiguration", .all),
  ("PallasResponseVerifier", .all),
]

private func inspectClasses(_ observation: Inspection, _ inspect: (String) -> [String: Any])
  -> [String: Any]
{
  Dictionary(
    uniqueKeysWithValues: inspectedClasses.filter { $0.1.contains(observation) }.map {
      ($0.0, inspect($0.0))
    })
}

private func inspectAssetSets(_ types: [String: String]) -> [String: Any] {
  var result: [String: Any] = [:]
  for (name, type) in types {
    var error: NSError?
    let status = paredLocalStatus(name, &error)
    let usages = paredUsageTypesForSet(name)
    let manager = usages == nil ? nil : bridgeConfigurationManager()
    let configuration = bridgeAssetSetWithManager(manager, name as NSString)
    let available = hasMethod(configuration, "usageValues", .assetSetUsage)
    let restrictions = available ? configuration.flatMap { objectValue($0, .usageValues) } : nil
    result[name] = [
      "catalogType": type, "runtimeType": paredAssetTypeForSet(name) as Any? ?? NSNull(),
      "usageTypes": usages as Any? ?? NSNull(), "usageValuesAvailable": available,
      "usageValues": restrictions ?? NSNull(), "snapshot": status.map(snapshot) as Any? ?? NSNull(),
      "error": errorDetails(error),
    ]
  }
  return result
}

private func inspectCatalogConfigurations(_ types: [String: String]) -> [String: Any] {
  Dictionary(
    uniqueKeysWithValues: Set(types.values).sorted().map { type in
      guard let configuration = paredCatalogRequestConfiguration(type) else {
        return (type, ["available": false] as [String: Any])
      }
      return (
        type,
        [
          "available": true, "endpoint": configuration.endpoint.absoluteString,
          "audience": configuration.audience, "productType": configuration.productType,
          "hardwareModel": configuration.hardwareModel,
          "productVersion": configuration.productVersion,
          "buildVersion": configuration.buildVersion,
        ] as [String: Any]
      )
    })
}

private func inspectPublishedCatalog(_ assetType: String) async throws -> [String: Any] {
  guard let configuration = paredCatalogRequestConfiguration(assetType) else {
    throw NSError(
      domain: "inspect-uaf", code: 69,
      userInfo: [NSLocalizedDescriptionKey: "Catalog configuration is unavailable"])
  }
  // Use the production HTTPS transport and decoder; retain summary counts only
  let catalog = try await paredFetchPublishedCatalog(assetType, configuration: configuration)
  return [
    "assetType": assetType, "publishedAssetCount": catalog.assets.count,
    "requestedTypeAssetCount": catalog.assets.filter { $0.identity.type == assetType }.count,
    "distinctIdentityCount": Set(catalog.assets.map(\.identity)).count,
    "decryptionKeysRemoved": catalog.assets.allSatisfy {
      $0.metadata["ArchiveDecryptionKey"] == nil
    },
    "independentEnvelopeSignatureVerified": false,
  ]
}

private func inspectForwardingReceivers() -> [String: Any] {
  let operation = ParedOperationService(errorHandler: { _ in })
  let diagnostic = ParedDiagnosticService(errorHandler: { _ in })
  defer {
    operation?.invalidate()
    diagnostic?.invalidate()
  }
  var result: [String: Any] = [:]
  for (name, method, receiver) in [
    ("operation", BridgeForwardedMethod.operation, operation?.proxy()),
    ("diagnostic", BridgeForwardedMethod.diagnostic, diagnostic?.proxy()),
  ] {
    guard let receiver else { continue }
    let concrete = class_getInstanceMethod(object_getClass(receiver), method.selector)
    result[name] = [
      "forwardingSignatureMatches": bridgeMessageDispatcher(receiver, method) != nil,
      "generatedMethodEncoding": concrete.flatMap(method_getTypeEncoding).map {
        String(cString: $0)
      } as Any? ?? NSNull(),
    ]
  }
  return result
}

private func archiveRoundTrip(_ object: AnyObject, _ bytes: inout Int, _ error: inout NSError?)
  -> AnyObject?
{
  do {
    let archive = try NSKeyedArchiver.archivedData(
      withRootObject: object, requiringSecureCoding: true)
    bytes = archive.count
    return try NSKeyedUnarchiver.unarchivedObject(ofClasses: [type(of: object)], from: archive)
      as AnyObject?
  } catch let caught as NSError {
    error = caught
    return nil
  }
}

private func inspectNativeSubscription(
  _ validated: ParedAssetSubscription, _ recovery: NSDictionary, _ details: inout [String: Any]
) {
  let name = recovery["name"] as! NSString
  let usages = recovery["assetSetUsages"] as? NSDictionary ?? NSDictionary()
  let aliases = recovery["usageAliases"] as! NSDictionary
  let type: AnyClass = NSClassFromString("UAFAssetSetSubscription")!
  guard let native = initializeSubscription(type, name, usages, aliases) as? NSObject else {
    return
  }
  let available = hasMethods(native, .subscriptionValues)
  details["nativeInputOwnershipAvailable"] = available
  if available {
    details["nativeRetainsName"] = objectValue(native, .name) === name
    details["nativeRetainsAssetSets"] = objectValue(native, .assetSets) === usages
    details["nativeRetainsUsageAliases"] = objectValue(native, .usageAliases) === aliases
    details["nativeHasExpiration"] = objectValue(native, .expiration) != nil
  }
  let bridgeNative = validated.native
  let snapshotAvailable = hasMethods(bridgeNative, .subscriptionValues)
  details["bridgeInputSnapshotAvailable"] = snapshotAvailable
  if snapshotAvailable {
    let sets = objectValue(bridgeNative, .assetSets) as! NSDictionary
    let snapshotAliases = objectValue(bridgeNative, .usageAliases) as! NSDictionary
    let nestedCopies = usages.allKeys.allSatisfy { key in
      (sets[key] as AnyObject?) !== (usages[key] as AnyObject?)
        && !(sets[key] is NSMutableDictionary)
    }
    details["bridgeInputSnapshot"] = [
      "nameEqual": (objectValue(bridgeNative, .name) as? NSObject)?.isEqual(name) == true,
      "assetSetsEqual": sets.isEqual(usages), "usageAliasesEqual": snapshotAliases.isEqual(aliases),
      "assetSetsCopied": sets !== usages, "usageAliasesCopied": snapshotAliases !== aliases,
      "nestedUsagesCopiedAndImmutable": nestedCopies,
      "assetSetsImmutable": !(sets is NSMutableDictionary),
      "usageAliasesImmutable": !(snapshotAliases is NSMutableDictionary),
    ]
    var error: NSError?
    var bytes = 0
    let decoded = archiveRoundTrip(bridgeNative, &bytes, &error)
    details["bridgeNativeEqual"] = native.isEqual(bridgeNative)
    details["bridgeSecureArchiveRoundTripEqual"] =
      (bridgeNative as? NSObject)?.isEqual(decoded) == true
    details["bridgeSecureArchiveError"] = errorDetails(error)
  }
  var error: NSError?
  var bytes = 0
  let decoded = archiveRoundTrip(native, &bytes, &error)
  details["secureArchiveBytes"] = bytes
  details["secureArchiveRoundTripEqual"] = native.isEqual(decoded)
  details["secureArchiveError"] = errorDetails(error)
}

private func inspectRecovery(_ recovery: NSDictionary) -> [String: Any] {
  let usages = recovery["assetSetUsages"] as AnyObject? ?? NSDictionary()
  let aliases = recovery["usageAliases"] as AnyObject?
  var resolved: [String: Any] = [:]
  if let aliases = aliases as? NSDictionary {
    for (alias, value) in aliases {
      guard let alias = alias as? NSString else { continue }
      resolved[alias as String] =
        bridgeResolveUsageAlias(alias, value as AnyObject) ?? NSNull()
    }
  }
  var error: NSError?
  let validated = bridgeSubscription(recovery["name"] as AnyObject?, usages, aliases, &error)
  var details: [String: Any] = [
    "validated": validated != nil, "validationError": errorDetails(error),
    "resolvedAliases": resolved,
  ]
  if let validated { inspectNativeSubscription(validated, recovery, &details) }
  return details
}

@main
private enum InspectUAF {
  static func main() async {
    let arguments = CommandLine.arguments
    guard
      arguments.count == 2
        || (arguments.count == 4 && arguments[2] == "--published-catalog")
    else {
      FileHandle.standardError.write(
        Data("Usage: inspect-uaf CATALOG.json [--published-catalog TYPE]\n".utf8))
      exit(64)
    }
    guard paredAssetRuntimeIsAvailable() else {
      FileHandle.standardError.write(Data("Cannot load UnifiedAssetFramework\n".utf8))
      exit(69)
    }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
      guard let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        var types = catalog["assetTypes"] as? [String: String],
        let features = catalog["features"] as? [String: NSDictionary]
      else {
        throw NSError(
          domain: "inspect-uaf", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Unknown catalog structure"])
      }
      #if arch(arm64)
        let architecture = "arm64"
      #else
        let architecture = "other"
      #endif
      types.merge(catalog["recoveryAssetTypes"] as? [String: String] ?? [:]) { _, new in new }
      // Load catalog classes before collecting their encodings and image UUIDs
      let configurations = inspectCatalogConfigurations(types)
      let versions = paredProcessVersions()
      var processError: NSError?
      let parent = paredInspectProcess(getppid(), &processError)
      var report: [String: Any] = [
        "os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": architecture,
        "methods": inspectClasses(.methods, methods),
        "implementations": inspectClasses(.implementations, implementations),
        "properties": inspectClasses(.properties, properties), "frameworkImages": frameworkImages(),
        "catalogConfigurations": configurations,
        "forwardingReceivers": inspectForwardingReceivers(),
        "bridgeDiagnosticInterfaceAvailable": paredDiagnosticServiceInterface() != nil,
        "processAPI": [
          "observedProcessCount": versions.count, "parentIdentityAvailable": parent != nil,
          "parentVersionMatches": parent.map { versions[$0.pid] == $0.version } == true,
          "error": errorDetails(processError),
        ],
      ]
      if arguments.count == 4 {
        guard Set(types.values).contains(arguments[3]) else {
          throw NSError(
            domain: "inspect-uaf", code: 64,
            userInfo: [NSLocalizedDescriptionKey: "Choose an asset type from the bundled catalog"])
        }
        report["publishedCatalog"] = try await inspectPublishedCatalog(arguments[3])
      }
      let interface = paredServiceInterface()
      report["bridgeInterfaceAvailable"] = interface != nil
      if let interface {
        let operation = NSSelectorFromString("operationWithConfig:completion:")
        let method = protocol_getMethodDescription(interface.protocol, operation, true, true)
        report["xpc"] = [
          "protocol": String(cString: protocol_getName(interface.protocol)),
          "operationEncoding": String(cString: method.types!),
          "requestClasses": classNames(
            interface.classes(for: operation, argumentIndex: 0, ofReply: false)),
          "replyClasses": classNames(
            interface.classes(for: operation, argumentIndex: 0, ofReply: true)),
        ]
      }
      report["assetSets"] = inspectAssetSets(types)
      var recoveries: [String: Any] = [:]
      for (name, feature) in features {
        if let recovery = feature["recovery"] as? NSDictionary {
          recoveries[name] = inspectRecovery(recovery)
        }
      }
      report["recoveries"] = recoveries
      let output = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      FileHandle.standardOutput.write(output)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(
        Data("Cannot collect report: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }
}
