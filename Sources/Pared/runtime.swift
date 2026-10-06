import AssetBridge
import Foundation

// Use the same exit codes for immediate failures and asynchronous XPC replies
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

// Require each operation's fields before building the XPC dictionary
// In particular, reset must include AssetSets: omitting it resets every set
enum ModelOperation {
  case reset(assetSets: [String])
  case subscribe(subscriber: String, subscriptions: [ParedAssetSubscription])
  case unsubscribe(subscriber: String, names: [String])

  func send(
    to proxy: NSObject, completion: @escaping (Error?) -> Void, error: inout NSError?
  ) -> Bool {
    switch self {
    case .reset(let assetSets):
      ParedPerformReset(proxy, assetSets, completion, &error)
    case .subscribe(let subscriber, let subscriptions):
      ParedPerformSubscribe(proxy, subscriber, subscriptions, completion, &error)
    case .unsubscribe(let subscriber, let names):
      ParedPerformUnsubscribe(proxy, subscriber, names, completion, &error)
    }
  }
}
