import AssetBridge
import Foundation

func recoverModels(
  _ names: [String], policy: Policy, catalog: Catalog, dryRun: Bool
) throws -> ExitStatus {
  guard !names.isEmpty else { throw CLIError("models download requires feature names") }
  let recoveries = try names.map { name -> ModelRecovery in
    guard policy.state(name) == .enabled else {
      throw CLIError("Enable \(name) in the selected policy before requesting its download")
    }
    guard let recovery = catalog.features[name]!.recovery else {
      throw CLIError(
        "No download subscription is available for \(name); enable it in its Apple app")
    }
    if let minimum = recovery.minimumOSMajorVersion,
      ProcessInfo.processInfo.operatingSystemVersion.majorVersion < minimum
    {
      throw CLIError("Recovery for \(name) requires macOS \(minimum) or newer")
    }
    return recovery
  }
  if dryRun {
    FileHandle.standardOutput.write(try jsonData(recoveries))
    return .success
  }
  try validateDownloadPreferences(policy: policy, catalog: catalog, names: names)
  guard
    dlopen(
      UnifiedAssets.framework,
      RTLD_NOW) != nil
  else { throw CLIError("Cannot load UnifiedAssetFramework") }
  let targets = catalog.assetSets(for: names, at: \.downloadAssetSets)
  let assets = try catalog.modelAssets(targets, includingDownloadDependencies: true)
  // The installed profile can still block downloads after the CLI policy
  // changes. Read the daemon's managed preferences and reject requests that
  // Pared's download override would redirect to loopback
  let block = catalog.downloadBlocking
  let managedURL = URL(fileURLWithPath: "/Library/Managed Preferences/\(block.domain).plist")
  if FileManager.default.fileExists(atPath: managedURL.path) {
    guard
      let managed = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: managedURL), format: nil) as? [String: Any]
    else { throw CLIError("Installed download policy has an unknown format; no request sent") }
    let blocked = assets.contains { asset in
      managed[block.keyPrefix + asset.assetType] as? String == block.url
    }
    guard !blocked else {
      throw CLIError(
        "Model downloads are still blocked by the installed policy. Install the updated profile before downloading."
      )
    }
  }
  do {
    for asset in assets { try asset.validateConfiguration() }
  } catch {
    report(String(describing: error))
    return .unavailable
  }
  for name in names {
    let feature = catalog.features[name]!
    let recovery = feature.recovery!
    // The bridge validates usage names and ENABLED values when constructing
    // subscriptions; this check keeps alias expansion inside the catalog scope
    for (alias, value) in recovery.usageAliases {
      guard
        let usages = paredResolveUsageAlias(alias, value),
        !usages.isEmpty,
        Set(usages.keys).isSubset(
          of: feature.downloadAssetSets)
      else { throw CLIError("Download alias no longer matches the catalog for \(name)") }
    }
  }
  let batches = try ModelSubscriptionBatch.prepare(recoveries)
  for batch in batches {
    // ResetAssetSets can leave requests intact; unsubscribe first to bypass
    // Subscribe's identical-subscription shortcut when restoring our request
    // Apple also compares specifiers across all subscribers, so unchanged
    // aggregate demand can still skip configuration and a new download
    // The operations are separate; a failed Subscribe can leave the restored
    // request absent or partially applied
    let refresh = unsubscribeModelRequests(batch.names, subscriber: batch.subscriber)
    guard refresh == .success else { return refresh }
    let result = modelOperation(.subscribe(batch)) { error, reply in
      if let error {
        reply.finish(
          .failure, message: "Subscription failed; partial changes are possible: \(error)")
      } else {
        reply.finish(
          .success, message: "Subscription accepted; download completion is not yet known")
      }
    }
    guard result == .success else { return result }
  }
  return .success
}

func unsubscribeModelRequests(_ names: [String], subscriber: String) -> ExitStatus {
  guard !names.isEmpty else { return .success }
  return modelOperation(.unsubscribe(subscriber: subscriber, names: names)) { error, reply in
    reply.finish(
      error == nil ? .success : .failure,
      message: error.map { "Unsubscribe reported an error; partial changes are possible: \($0)" }
        ?? "Unsubscribe accepted for selected download requests for \(subscriber)")
  }
}
