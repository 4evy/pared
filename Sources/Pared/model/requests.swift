import AssetBridge
import Foundation

struct ModelAssetSet {
  let name: String
  let assetType: String

  func validateConfiguration() throws(CLIError) {
    guard ParedAssetTypeForSet(name) == assetType else {
      throw CLIError("Asset type does not match the catalog for \(name); no request sent")
    }
  }
}

struct ModelSubscriptionBatch {
  let subscriber: String
  private let subscriptions: [Subscription]

  var names: [String] { subscriptions.map(\.name) }

  private struct Subscription {
    let name: String
    let native: ParedAssetSubscription

    init(_ recovery: ModelRecovery) throws {
      var error: NSError?
      guard
        let native = ParedSubscription(
          recovery.name,
          (recovery.assetSetUsages ?? [:]).mapValues { $0.mapValues(\.rawValue) },
          recovery.usageAliases, &error)
      else {
        if let error { throw error }
        throw CLIError("Cannot construct download subscription; no request sent")
      }
      name = recovery.name
      self.native = native
    }
  }

  private init(subscriber: String, recoveries: [ModelRecovery]) throws {
    guard !subscriber.isEmpty, !recoveries.isEmpty,
      Set(recoveries.map(\.name)).count == recoveries.count
    else {
      throw CLIError("Download requests require a subscriber and unique names; no request sent")
    }
    self.subscriber = subscriber
    subscriptions = try recoveries.map(Subscription.init)
  }

  // Prepare every replacement before removing or sending any requests
  static func prepare(_ recoveries: [ModelRecovery]) throws -> [Self] {
    try Dictionary(grouping: recoveries, by: \.subscriber)
      .sorted { $0.key < $1.key }
      .map { try Self(subscriber: $0.key, recoveries: $0.value) }
  }

  fileprivate func send(
    to proxy: NSObject, completion: @escaping (Error?) -> Void, error: inout NSError?
  ) -> Bool {
    ParedPerformSubscribe(proxy, subscriber, subscriptions.map(\.native), completion, &error)
  }
}

// Reset must name its asset sets; omitting them resets every set
enum ModelOperation {
  case reset(assetSets: [String])
  case subscribe(ModelSubscriptionBatch)
  case unsubscribe(subscriber: String, names: [String])

  func send(to proxy: NSObject, completion: @escaping (Error?) -> Void) throws {
    var error: NSError?
    let sent =
      switch self {
      case .reset(let assetSets):
        ParedPerformReset(proxy, assetSets, completion, &error)
      case .subscribe(let batch):
        batch.send(to: proxy, completion: completion, error: &error)
      case .unsubscribe(let subscriber, let names):
        ParedPerformUnsubscribe(proxy, subscriber, names, completion, &error)
      }
    guard sent else {
      if let error { throw error }
      throw CLIError("The bridge rejected the model request")
    }
  }
}
