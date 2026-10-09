import Foundation

// Each dispatch family fixes the argument ABI; its cases fix the contract
// Object encodings cannot describe collection contents or nullability, so
// callers still validate returned values before creating public snapshots
enum BridgeObjectGetter: String {
  case defaultManager, defaultInterface
  case usageTypes, usageValues, autoAssetType
  case name, assetSets, usageAliases, expiration
  case uuid, url
  case latestDownloadedAtomicInstance, configuredAssetEntries
  case latestDowloadedAtomicInstanceEntries
  case assetID, fullAssetSelector
  case assetType, assetSpecifier, assetVersion

  var contractName: BridgeContract {
    switch self {
    case .defaultManager: .configurationManager
    case .defaultInterface: .serviceInterface
    case .usageTypes, .usageValues: .assetSetUsage
    case .autoAssetType: .assetSetConfiguration
    case .name, .assetSets, .usageAliases, .expiration:
      .subscriptionValues
    case .uuid, .url: .catalogConfigurationValues
    case .latestDownloadedAtomicInstance, .configuredAssetEntries,
      .latestDowloadedAtomicInstanceEntries:
      .assetSetStatusObjects
    case .assetID, .fullAssetSelector: .downloadedEntry
    case .assetType, .assetSpecifier, .assetVersion: .autoAssetSelector
    }
  }
}

enum BridgeStringQuery: String {
  case assetSet = "getAssetSet:"
  case catalogConfiguration = "pallasConfigurationForAssetType:"

  var contractName: BridgeContract {
    switch self {
    case .assetSet: .configurationManager
    case .catalogConfiguration: .catalogConfiguration
    }
  }
}

enum BridgeBoolGetter: String {
  case supportsSecureCoding, vendingAtomicInstanceForConfiguredEntries

  var contractName: BridgeContract {
    switch self {
    case .supportsSecureCoding: .secureCoding
    case .vendingAtomicInstanceForConfiguredEntries:
      .assetSetStatusScalars
    }
  }
}

enum BridgeInt64Getter: String {
  case downloadedNetworkBytes, downloadedFilesystemBytes
}
