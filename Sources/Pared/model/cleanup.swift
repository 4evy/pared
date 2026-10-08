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
    let broker = ModelBrokerInventory()
    // Warn before cancelling subscriptions or requesting removal, since the
    // reset reply cannot substitute for an unreadable payload inventory
    for asset in assets {
      do {
        _ = try modelPayloadDirectories(assetType: asset.assetType, broker: broker)
      } catch {
        let reason =
          modelInventoryAccessDenied(error)
          ? "macOS denied access to the model folder"
          : error.localizedDescription
        report(
          "\(catalog.modelTitle(asset.name)): \(reason). Folder verification is unavailable before removal. The request can proceed, but an accepted reply alone will not confirm deletion."
        )
      }
    }
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
  let resetStarted = Date()
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
          "macOS reported locks during removal. Its reset routine can retain that error after attempting forced removal, so check model folders before assuming the locks remain. Keep the matching profile installed to block downloads."
        )
      }
      reply.finish(
        .failure, message: "Reset reported an error; partial removal is possible: \(error)")
    } else {
      reply.finish(
        .success,
        message: "macOS accepted the removal request; checking whether model folders remain")
    }
  }
  // Do not follow an unknown transport outcome with another request or label
  // daemon acknowledgement as deletion. Inventory reads do not hold UAF locks
  guard !check, result == .success || result == .failure else { return result }
  let titles = Dictionary(
    assets.map { ($0.name, catalog.modelTitle($0.name)) }, uniquingKeysWith: { first, _ in first })
  let inventory = verifyModelRemoval(assets, titles: titles)
  // Reset can retain its initial lock error after forced removal succeeds
  // A readable, empty inventory establishes the requested outcome anyway
  if inventory == .success { return .success }
  if inventory == .verificationUnavailable {
    let types = Set(assets.map(\.assetType))
    let evidence = modelEliminationEvidence(since: resetStarted, assetTypes: types)
    if evidence.assetTypes == types {
      report(ModelEliminationEvidence.confirmation)
      report(
        "The daemon reported no remaining matching payload descriptors or locked payloads. Direct folder verification and reclaimed disk space remain unavailable."
      )
      return .verificationUnavailable
    }
  }
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

private enum ModelRemovalObservation: Hashable {
  case removed, remaining, unavailable, accessDenied
}

func verifyModelRemoval(
  _ assets: [ModelAssetSet], root: URL = UnifiedAssets.assetDirectory,
  titles: [String: String] = [:]
) -> ExitStatus {
  let broker = ModelBrokerInventory()
  let observations = Set(
    assets.map { asset -> ModelRemovalObservation in
      let title = titles[asset.name] ?? asset.name
      do {
        let paths = try modelPayloadDirectories(
          assetType: asset.assetType, root: root, broker: broker)
        guard !paths.isEmpty else { return .removed }
        report("\(title): \(paths.count) model folder(s) remain; removal is incomplete")
        return .remaining
      } catch {
        if modelInventoryAccessDenied(error) {
          report(
            "\(title): macOS denied access to the model folder; removal could not be checked")
          return .accessDenied
        }
        report("\(title): removal could not be checked: \(error.localizedDescription)")
        return .unavailable
      }
    })
  let remaining = observations.contains(.remaining)
  let accessDenied = observations.contains(.accessDenied)
  let unreadable = !observations.isDisjoint(with: [.unavailable, .accessDenied])
  if !remaining && !unreadable {
    report("No model folders remain for the selected sets; reclaimed disk space was not measured")
  }
  if accessDenied {
    report("A folder access error does not mean models are in use or that removal failed.")
    report(
      "Check Full Disk Access in System Settings > Privacy & Security for the current Pared build or terminal app, then reopen it. System-protected model storage can also require restricted entitlements that sudo and Full Disk Access cannot supply. Run pared models status to check again without repeating removal."
    )
  }
  if remaining {
    report(
      "macOS may still be finishing removal or keeping models in use. Check pared models status again; if folders remain, inspect MobileAsset deletion logs for locks before closing apps or restarting."
    )
  } else if unreadable {
    report("Removal is unverified; Pared could not inspect every selected model folder.")
  }
  if remaining { return .failure }
  return unreadable ? .verificationUnavailable : .success
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
