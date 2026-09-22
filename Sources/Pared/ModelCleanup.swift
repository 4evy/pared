import AssetBridge
import Foundation

// Keep speech, OCR, handwriting, and configuration/safety overrides excluded
func validate(_ targets: [String], assetTypes: [String: String]) -> Bool {
  for name in targets {
    guard let actual = ParedAssetTypeForSet(name),
      actual == assetTypes[name]
    else {
      report("Asset type does not match the catalog for \(name); no request sent")
      return false
    }
  }
  return true
}

func checkService(catalog: Catalog) -> ExitStatus {
  resetModels([UnifiedAssets.checkTarget], catalog: catalog)
}

func resetModels(_ targets: [String], catalog: Catalog) -> ExitStatus {
  guard !targets.isEmpty else {
    report("No asset sets selected; no request sent")
    return .success
  }
  guard dlopen(UnifiedAssets.framework, RTLD_NOW) != nil else {
    report("Cannot load UnifiedAssetFramework")
    return .unavailable
  }
  let check = targets == [UnifiedAssets.checkTarget]
  guard validate(check ? catalog.assetTypes.keys.sorted() : targets, assetTypes: catalog.assetTypes)
  else {
    return .unavailable
  }
  if !check {
    // Stop only requests created by pared. Apple's and other apps' subscribers
    // remain their responsibility; cleanup still depends on the feature policy
    let selected = Set(targets)
    let requests = catalog.features.values.compactMap { feature -> String? in
      guard let recovery = feature.recovery, recovery.subscriber == UnifiedAssets.subscriber,
        !selected.isDisjoint(with: feature.assetSets)
      else { return nil }
      return recovery.name
    }
    let result = unsubscribeModelRequests(requests, subscriber: UnifiedAssets.subscriber)
    guard result == .success else { return result }
  }
  // Never omit AssetSets: the server interprets nil as every asset set
  return modelOperation(.reset(assetSets: targets)) { error, reply in
    if check {
      let missing = error?.userInfo[UnifiedAssets.checkTarget] as? NSError
      let reachedHandler =
        error?.domain == UnifiedAssets.errorDomain
        && error?.code == UnifiedAssets.missingConfigurationCode
        && missing?.localizedFailureReason == UnifiedAssets.missingConfigurationReason
      reply.finish(
        reachedHandler ? .success : .failure,
        message: reachedHandler
          ? "Reached reset handler with a nonexistent set; no real assets selected"
          : "Could not reach the reset handler: \(String(describing: error))")
    } else if let error {
      reply.finish(
        .failure, message: "Reset reported an error; partial removal is possible: \(error)")
    } else {
      reply.finish(
        .success,
        message: "Reset returned successfully; check MobileAsset deletion logs and free space")
    }
  }
}

func modelOperation(
  _ operation: ModelOperation, completion handler: @escaping (NSError?, Reply<ExitStatus>) -> Void
) -> ExitStatus {
  // Use Apple's interface to preserve its oneway Objective-C signature and
  // allowed classes. A plain Swift protocol produces an incompatible wire signature
  guard
    let interface = UnifiedAssets.serviceInterface
  else {
    report("Required private XPC interface is unavailable")
    return .unavailable
  }
  let connection = NSXPCConnection(machServiceName: UnifiedAssets.service, options: [])
  connection.remoteObjectInterface = interface
  connection.resume()
  defer { connection.invalidate() }
  let reply = Reply<ExitStatus>()
  guard
    let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
      reply.finish(
        .outcomeUnknown, message: "XPC transport error; request outcome may be unknown: \(error)")
    }) as? NSObject
  else {
    report("Cannot create subscription service proxy")
    return .unavailable
  }
  ParedPerformOperation(proxy, operation.configuration) { handler($0 as NSError?, reply) }
  return reply.wait()
}
