import Foundation
import ObjectiveC

// Runtime protocols keep the same validation interface as compiler declarations
// Offsets are omitted: NSMethodSignature compares types independently of them
// V preserves the daemon's oneway return qualifier, which Swift cannot declare
#if arch(x86_64)
  private let boolEncoding = "c"
#else
  private let boolEncoding = "B"
#endif

private let declarations: [String: [(String, String, Bool)]] = [
  "ParedConfigurationManagerAPI": [
    ("defaultManager", "@@:", false),
    ("getAssetSet:", "@@:@", true),
    ("getAssetSetUsagesForUsageAlias:usageAliasValue:", "@@:@@", true),
  ],
  "ParedAssetSetUsageAPI": [("usageTypes", "@@:", true), ("usageValues", "@@:", true)],
  "ParedAssetSetConfigurationAPI": [("autoAssetType", "@@:", true)],
  "ParedSubscriptionValuesAPI": [
    ("name", "@@:", true), ("assetSets", "@@:", true),
    ("usageAliases", "@@:", true), ("expiration", "@@:", true),
  ],
  "ParedSubscriptionAPI": [
    ("initWithName:assetSets:usageAliases:", "@@:@@@", true),
    ("isValid:error:", "\(boolEncoding)@:@^@", true),
  ],
  "ParedServiceInterfaceAPI": [("defaultInterface", "@@:", false)],
  "ParedServiceAPI": [("operationWithConfig:completion:", "Vv@:@@?", true)],
  "ParedDiagnosticServiceAPI": [("diagnosticInformation:", "Vv@:@?", true)],
  "ParedCatalogConfigurationAPI": [("pallasConfigurationForAssetType:", "@@:@", false)],
  "ParedCatalogConfigurationValuesAPI": [("uuid", "@@:", true), ("url", "@@:", true)],
  "ParedAutoAssetManagerAPI": [("latestStatusForClients:error:", "@@:@^@", false)],
  "ParedAssetSetStatusObjectsAPI": [
    ("latestDownloadedAtomicInstance", "@@:", true),
    ("configuredAssetEntries", "@@:", true),
    ("latestDowloadedAtomicInstanceEntries", "@@:", true),
  ],
  "ParedAssetSetStatusScalarsAPI": [
    ("downloadedNetworkBytes", "q@:", true),
    ("downloadedFilesystemBytes", "q@:", true),
    ("vendingAtomicInstanceForConfiguredEntries", "\(boolEncoding)@:", true),
  ],
  "ParedDownloadedEntryAPI": [("assetID", "@@:", true), ("fullAssetSelector", "@@:", true)],
  "ParedAutoAssetSelectorAPI": [
    ("assetType", "@@:", true), ("assetSpecifier", "@@:", true),
    ("assetVersion", "@@:", true),
  ],
]

// Swift initializes this once, serializing registration before any bridge call
nonisolated(unsafe) let bridgeContracts: [String: Protocol] = {
  var result = Dictionary(
    uniqueKeysWithValues: declarations.map { name, methods in
      // Keep production contracts independent of the test fixture's encodings
      let runtimeName = "ParedSwiftContract" + name
      let declaration = objc_allocateProtocol(runtimeName)!
      for (name, encoding, instance) in methods {
        encoding.withCString {
          protocol_addMethodDescription(declaration, NSSelectorFromString(name), $0, true, instance)
        }
      }
      objc_registerProtocol(declaration)
      return (name, declaration)
    })
  result["NSSecureCoding"] = NSSecureCoding.self
  result["NSCoding"] = NSCoding.self
  return result
}()
