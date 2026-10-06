import AssetBridge
import Foundation

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
  let assets: [ModelAssetSet]
  do {
    assets = try catalog.modelAssets(check ? catalog.assetTypes.keys.sorted() : targets)
    for asset in assets { try asset.validateConfiguration() }
  } catch {
    report(String(describing: error))
    return .unavailable
  }
  if !check {
    // Cancel Pared's subscriptions for the selected sets so they do not request
    // the models again; leave subscriptions owned by Apple or other apps alone
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
  let result = modelOperation(.reset(assetSets: targets)) { error, reply in
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
      if removalHasLocks(error) {
        report(
          "macOS reports models still in use. Close affected apps, log out or restart, then check pared models status before retrying cleanup. Keep the matching profile installed to block downloads."
        )
      }
      reply.finish(
        .failure, message: "Reset reported an error; partial removal is possible: \(error)")
    } else {
      reply.finish(
        .success,
        message: "Reset returned successfully; checking remaining model folders")
    }
  }
  // Do not follow an unknown transport outcome with another request or label
  // daemon acknowledgement as deletion. Inventory reads do not hold UAF locks
  guard !check, result == .success || result == .failure else { return result }
  let inventory = verifyModelRemoval(assets)
  return result == .success ? inventory : result
}

func removalHasLocks(_ error: NSError, depth: Int = 0) -> Bool {
  guard depth < 8 else { return false }
  if let usage = error.userInfo["currentLockUsage"] as? NSDictionary, usage.count > 0 {
    return true
  }
  if error.localizedFailureReason == "Could not eliminate as there are current locks" {
    return true
  }
  return error.userInfo.values.contains {
    guard let nested = $0 as? NSError else { return false }
    return removalHasLocks(nested, depth: depth + 1)
  }
}

func verifyModelRemoval(
  _ assets: [ModelAssetSet], root: URL = UnifiedAssets.assetDirectory
) -> ExitStatus {
  var complete = true
  for asset in assets {
    do {
      let paths = try modelPayloadDirectories(assetType: asset.assetType, root: root)
      if !paths.isEmpty {
        complete = false
        report("\(asset.name): \(paths.count) model folder(s) remain; removal is incomplete")
      }
    } catch {
      complete = false
      report("\(asset.name): cannot verify removal: \(error)")
    }
  }
  if complete {
    report("No model folders remain for the selected sets; reclaimed disk space was not measured")
  } else {
    report(
      "Check pared models status and MobileAsset deletion logs. macOS may defer deletion of files still in use; close affected apps or restart before checking again."
    )
  }
  return complete ? .success : .failure
}

func modelOperation(
  _ operation: ModelOperation, completion handler: @escaping (NSError?, Reply<ExitStatus>) -> Void
) -> ExitStatus {
  // Apple's interface supplies the oneway method signature and allowed object
  // classes; a plain Swift protocol produces an incompatible XPC message
  // Asset removal runs in the daemon; calling UAFAutoAssetManager's removal
  // helpers directly as a non-root process can return nil without removing
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
  do {
    try operation.send(to: proxy) { handler($0 as NSError?, reply) }
  } catch {
    report("Cannot send model request: \(error)")
    return .unavailable
  }
  return reply.wait()
}
