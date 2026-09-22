import AssetBridge
import Foundation

// Process results shared by the CLI and asynchronous service replies
enum ExitStatus: Int32 {
  case success = 0
  case failure = 1
  case outcomeUnknown = 2
  case unavailable = 69
}

enum Artifacts {
  static let profileFilename = "pared.mobileconfig"
  static let declarationsFilename = "declarations.json"
  static let policyFilename = "policy.json"
  static let applicationDirectory = "Library/Application Support/pared"
}

enum UnifiedAssets {
  static let framework =
    "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework"
  static let service = "com.apple.siri.uaf.subscription.service"
  static let subscriber = "org.pared"
  static let checkTarget = "org.pared.nonexistent.readonly-validation"
  static let errorDomain = "com.apple.UnifiedAssetFramework"
  static let missingConfigurationCode = -1
  static let missingConfigurationReason = "Could not get config"
  static let replyTimeout: TimeInterval = 45
  static let assetDirectory = URL(fileURLWithPath: "/System/Library/AssetsV2", isDirectory: true)
  static let assetExtension = "asset"
  static var serviceInterface: NSXPCInterface? { ParedServiceInterface() }
}

// Keep required fields attached to their operation. Only the transport boundary
// constructs Apple's heterogeneous dictionary; reset can never omit AssetSets
enum ModelOperation {
  case reset(assetSets: [String])
  case subscribe(subscriber: String, subscriptions: [NSObject])
  case unsubscribe(subscriber: String, names: [String])

  var configuration: [String: Any] {
    switch self {
    case .reset(let assetSets):
      return ["Operation": "ResetAssetSets", "AssetSets": assetSets]
    case .subscribe(let subscriber, let subscriptions):
      return [
        "Operation": "Subscribe", "Subscriber": subscriber,
        "Subscriptions": subscriptions, "UserInitiated": true,
      ]
    case .unsubscribe(let subscriber, let names):
      return [
        "Operation": "Unsubscribe", "Subscriber": subscriber,
        "Subscriptions": Set(names).sorted(), "UserInitiated": true,
      ]
    }
  }
}
