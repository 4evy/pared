import Foundation
import ObjectiveC

enum BridgeContract: String {
  case allocation = "ParedAllocationAPI"
  case configurationManager = "ParedConfigurationManagerAPI"
  case assetSetUsage = "ParedAssetSetUsageAPI"
  case assetSetConfiguration = "ParedAssetSetConfigurationAPI"
  case subscriptionValues = "ParedSubscriptionValuesAPI"
  case subscription = "ParedSubscriptionAPI"
  case serviceInterface = "ParedServiceInterfaceAPI"
  case operationService = "ParedServiceAPI"
  case diagnosticService = "ParedDiagnosticServiceAPI"
  case operationReceiver = "ParedOperationReceiverAPI"
  case diagnosticReceiver = "ParedDiagnosticReceiverAPI"
  case messageSignature = "ParedMessageSignatureAPI"
  case catalogConfiguration = "ParedCatalogConfigurationAPI"
  case catalogConfigurationValues = "ParedCatalogConfigurationValuesAPI"
  case autoAssetManager = "ParedAutoAssetManagerAPI"
  case assetSetStatusObjects = "ParedAssetSetStatusObjectsAPI"
  case assetSetStatusScalars = "ParedAssetSetStatusScalarsAPI"
  case downloadedEntry = "ParedDownloadedEntryAPI"
  case autoAssetSelector = "ParedAutoAssetSelectorAPI"
  case secureCoding = "NSSecureCoding"
  case coding = "NSCoding"
}

// Let the compiler generate selector encodings, including platform BOOL types
// AnyObject keeps object encodings open; returned values are checked separately
@objc private protocol ConfigurationManagerContract {
  static func defaultManager() -> AnyObject?
  @objc(getAssetSet:) func assetSet(_ name: NSString) -> AnyObject?
  @objc(getAssetSetUsagesForUsageAlias:usageAliasValue:) func usages(
    _ alias: NSString, value: NSString
  ) -> AnyObject?
}

@objc private protocol AssetSetUsageContract {
  var usageTypes: AnyObject? { get }
  var usageValues: AnyObject? { get }
}

@objc private protocol AssetSetConfigurationContract {
  var autoAssetType: AnyObject? { get }
}

@objc private protocol SubscriptionValuesContract {
  var name: AnyObject? { get }
  var assetSets: AnyObject? { get }
  var usageAliases: AnyObject? { get }
  var expiration: AnyObject? { get }
}

@objc private protocol SubscriptionContract {
  @objc(initWithName:assetSets:usageAliases:) func initialize(
    _ name: NSString, sets: NSDictionary, aliases: NSDictionary
  ) -> AnyObject?
  @objc(isValid:error:) func valid(
    _ manager: AnyObject, error: AutoreleasingUnsafeMutablePointer<AnyObject?>
  ) -> ObjCBool
}

@objc private protocol ServiceInterfaceContract {
  static func defaultInterface() -> AnyObject?
}

@objc private protocol OperationReceiverContract {
  @objc(operationWithConfig:completion:) func operation(
    _ configuration: NSDictionary, completion: @escaping BridgeCompletion)
}

@objc private protocol DiagnosticReceiverContract {
  @objc(diagnosticInformation:) func diagnostic(
    _ completion: @escaping @convention(block) (NSString?, NSError?) -> Void)
}

@objc private protocol MessageSignatureContract {
  @objc(methodSignatureForSelector:) func signature(_ selector: Selector) -> AnyObject?
}

@objc private protocol CatalogConfigurationContract {
  @objc(pallasConfigurationForAssetType:) static func configuration(_ type: NSString) -> AnyObject?
}

@objc private protocol CatalogConfigurationValuesContract {
  var uuid: AnyObject? { get }
  var url: AnyObject? { get }
}

@objc private protocol AutoAssetManagerContract {
  @objc(latestStatusForClients:error:) static func status(
    _ name: NSString, error: AutoreleasingUnsafeMutablePointer<AnyObject?>
  ) -> AnyObject?
}

@objc private protocol AssetSetStatusObjectsContract {
  var latestDownloadedAtomicInstance: AnyObject? { get }
  var configuredAssetEntries: AnyObject? { get }
  var latestDowloadedAtomicInstanceEntries: AnyObject? { get }
}

@objc private protocol AssetSetStatusScalarsContract {
  var downloadedNetworkBytes: Int64 { get }
  var downloadedFilesystemBytes: Int64 { get }
  var vendingAtomicInstanceForConfiguredEntries: ObjCBool { get }
}

@objc private protocol DownloadedEntryContract {
  var assetID: AnyObject? { get }
  var fullAssetSelector: AnyObject? { get }
}

@objc private protocol AutoAssetSelectorContract {
  var assetType: AnyObject? { get }
  var assetSpecifier: AnyObject? { get }
  var assetVersion: AnyObject? { get }
}

// Swift cannot declare alloc or the XPC oneway qualifier
// Derive their encodings from NSObject and the compiled receiver contracts
private func allocationContract() -> Protocol {
  let declaration = objc_allocateProtocol("ParedSwiftAllocationContract")!
  let selector = NSSelectorFromString("alloc")
  let method = class_getClassMethod(NSObject.self, selector)!
  protocol_addMethodDescription(declaration, selector, method_getTypeEncoding(method), true, false)
  objc_registerProtocol(declaration)
  return declaration
}

private func onewayContract(_ name: String, receiver: Protocol) -> Protocol {
  let declaration = objc_allocateProtocol(name)!
  var count: UInt32 = 0
  let methods = protocol_copyMethodDescriptionList(receiver, true, true, &count)!
  defer { free(methods) }
  for method in UnsafeBufferPointer(start: methods, count: Int(count)) {
    let encoding = "V" + String(cString: method.types!)
    encoding.withCString {
      protocol_addMethodDescription(declaration, method.name!, $0, true, true)
    }
  }
  objc_registerProtocol(declaration)
  return declaration
}

// Swift initializes this once before any bridge call registers special cases
nonisolated(unsafe) let bridgeContracts: [BridgeContract: Protocol] = [
  .allocation: allocationContract(),
  .configurationManager: ConfigurationManagerContract.self,
  .assetSetUsage: AssetSetUsageContract.self,
  .assetSetConfiguration: AssetSetConfigurationContract.self,
  .subscriptionValues: SubscriptionValuesContract.self,
  .subscription: SubscriptionContract.self,
  .serviceInterface: ServiceInterfaceContract.self,
  .operationService: onewayContract(
    "ParedSwiftOperationServiceContract", receiver: OperationReceiverContract.self),
  .diagnosticService: onewayContract(
    "ParedSwiftDiagnosticServiceContract", receiver: DiagnosticReceiverContract.self),
  .operationReceiver: OperationReceiverContract.self,
  .diagnosticReceiver: DiagnosticReceiverContract.self,
  .messageSignature: MessageSignatureContract.self,
  .catalogConfiguration: CatalogConfigurationContract.self,
  .catalogConfigurationValues: CatalogConfigurationValuesContract.self,
  .autoAssetManager: AutoAssetManagerContract.self,
  .assetSetStatusObjects: AssetSetStatusObjectsContract.self,
  .assetSetStatusScalars: AssetSetStatusScalarsContract.self,
  .downloadedEntry: DownloadedEntryContract.self,
  .autoAssetSelector: AutoAssetSelectorContract.self,
  .secureCoding: NSSecureCoding.self,
  .coding: NSCoding.self,
]
