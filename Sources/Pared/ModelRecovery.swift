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
  let targets = Set(
    names.flatMap { name in
      let feature = catalog.features[name]!
      return feature.assetSets + (feature.recovery?.additionalAssetSets ?? [])
    }
  ).sorted()
  // Enabling the CLI policy does not replace the installed system profile.
  // Check the same managed plist the daemon reads before accepting a request
  // that our download block would send to loopback.
  let block = catalog.downloadBlocking
  let managedURL = URL(fileURLWithPath: "/Library/Managed Preferences/\(block.domain).plist")
  if FileManager.default.fileExists(atPath: managedURL.path) {
    guard
      let managed = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: managedURL), format: nil) as? [String: Any]
    else { throw CLIError("Installed download policy has an unknown format; no request sent") }
    let blocked = targets.contains { target in
      guard let type = catalog.downloadAssetTypes[target] else { return false }
      return managed[block.keyPrefix + type] as? String == block.url
    }
    guard !blocked else {
      throw CLIError(
        "Model downloads are still blocked by the installed policy. Install the updated profile before downloading."
      )
    }
  }
  guard validate(targets, assetTypes: catalog.downloadAssetTypes) else { return .unavailable }
  for name in names {
    let feature = catalog.features[name]!
    let recovery = feature.recovery!
    for (set, usages) in recovery.assetSetUsages ?? [:] {
      guard
        let known = ParedUsageTypesForSet(set),
        !usages.isEmpty, Set(usages.keys).isSubset(of: known)
      else { throw CLIError("Download usages no longer match the catalog for \(name)") }
    }
    for (alias, value) in recovery.usageAliases {
      guard
        let usages = ParedResolveUsageAlias(alias, value),
        !usages.isEmpty,
        Set(usages.keys).isSubset(
          of: feature.assetSets + (recovery.additionalAssetSets ?? []))
      else { throw CLIError("Download alias no longer matches the catalog for \(name)") }
      for (set, resolved) in usages {
        guard let known = ParedUsageTypesForSet(set),
          !resolved.isEmpty, Set(resolved.keys).isSubset(of: known),
          resolved.values.allSatisfy({ ModelUsage(rawValue: $0) == .enabled })
        else { throw CLIError("Download alias contains unsupported usages for \(name)") }
      }
    }
  }
  // Construct every subscription before sending any request. Use Apple's secure
  // coding objects and XPC interface instead of reproducing their wire format
  let subscriptions = try recoveries.map {
    recovery -> (subscriber: String, name: String, object: NSObject) in
    guard
      let subscription = ParedSubscription(
        recovery.name, (recovery.assetSetUsages ?? [:]).mapValues { $0.mapValues(\.rawValue) },
        recovery.usageAliases)
    else {
      throw CLIError("Required subscription initializer is unavailable")
    }
    return (recovery.subscriber, recovery.name, subscription)
  }
  for (subscriber, entries) in Dictionary(grouping: subscriptions, by: \.subscriber) {
    // ResetAssetSets can leave subscriptions intact. Repeating Subscribe then
    // does nothing, so refresh only the named subscriptions in this catalog
    // Failure between operations can leave the subscription absent
    let refresh = unsubscribeModelRequests(entries.map(\.name), subscriber: subscriber)
    guard refresh == .success else { return refresh }
    let result = modelOperation(
      .subscribe(subscriber: subscriber, subscriptions: entries.map(\.object))
    ) { error, reply in
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
      message: error.map { "Cannot remove selected download requests: \($0)" }
        ?? "Removed selected download requests for \(subscriber)")
  }
}
