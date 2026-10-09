import Foundation

struct FeatureStatus: Codable {
  let desired: FeatureState
  let preferences: [PreferenceStatus]
  let managementRequired: Bool
  let modelAvailabilityOnly: Bool
}

func executeCommand(
  _ command: Command, names requestedNames: [String], policyURL: URL?, dryRun: Bool,
  cleanupReview: Bool = false, reviewedAssetSets: [String]? = nil
) throws -> ExitStatus {
  let catalog = try Catalog.load()
  let url = policyURL ?? Policy.defaultURL
  let names = try catalog.selectedFeatureNames(requestedNames)
  if command == .features {
    for (name, feature) in catalog.features.sorted(by: { $0.key < $1.key }) {
      print("\(name): \(feature.description) [\(feature.controls.joined(separator: ", "))]")
    }
    return .success
  }
  if command == .check { return checkService(catalog: catalog) }
  var policy = try Policy.load(url, explicit: policyURL != nil, catalog: catalog)
  if let state = command.desiredState {
    guard !names.isEmpty else {
      throw CLIError("\(command.rawValue) requires feature names or 'all'")
    }
    policy.set(state, for: names)
  }
  let selected = names.isEmpty ? catalog.featureNames : names
  switch command {
  case .status:
    let status = Dictionary(
      uniqueKeysWithValues: selected.map { name in
        let feature = catalog.features[name]!
        return (
          name,
          FeatureStatus(
            desired: policy.state(name), preferences: feature.preferences.map(preferenceStatus),
            managementRequired: feature.managementRequired,
            modelAvailabilityOnly: feature.modelAvailabilityOnly)
        )
      })
    FileHandle.standardOutput.write(try jsonData(status))
    report("Desired policy is not proof of runtime enforcement. Null means no observed preference.")
  case .profile: FileHandle.standardOutput.write(try profileData(policy: policy, catalog: catalog))
  case .openProfile:
    try openProfileInstallation(policy: policy, catalog: catalog)
  case .profileStatus:
    return try reportProfileInstallation()
  case .declarations:
    FileHandle.standardOutput.write(try declarationData(policy: policy, catalog: catalog))
  case .download:
    return try recoverModels(
      names.isEmpty ? [] : selected, policy: policy, catalog: catalog, dryRun: dryRun)
  case .models:
    let targets = catalog.assetSets(for: selected)
    let statuses = try modelStatus(targets, catalog: catalog)
    FileHandle.standardOutput.write(try jsonData(statuses))
    return statuses.contains(where: \.hasErrors)
      ? .failure : .success
  case .cleanup:
    let requested = Set(catalog.assetSets(for: selected))
    var targets = policy.cleanupTargets(catalog).filter { requested.contains($0) }
    if let reviewedAssetSets {
      let selection = Set(reviewedAssetSets)
      guard !selection.isEmpty,
        selection.count == reviewedAssetSets.count,
        selection.isSubset(of: Set(targets))
      else {
        throw CLIError(
          "Every selected asset set must be unique and eligible under the policy; no request sent")
      }
      targets = reviewedAssetSets.sorted()
    }
    if cleanupReview {
      FileHandle.standardOutput.write(
        try jsonData(ModelCleanupPlan.prepare(targets, catalog: catalog)))
      return .success
    }
    if dryRun {
      FileHandle.standardOutput.write(try jsonData(targets))
      return .success
    }
    return resetModels(targets, catalog: catalog)
  case .enable, .disable, .reset, .apply:
    if dryRun {
      FileHandle.standardOutput.write(try jsonData(policy))
      return .success
    }
    try persistPolicyChanges(
      policy: policy, url: url, catalog: catalog, names: selected, reset: command == .reset)
  case .features, .check:
    preconditionFailure("Handled before policy loading")
  }
  return .success
}

func persistPolicyChanges(
  policy: Policy, url: URL, catalog: Catalog, names: [String], reset: Bool,
  reportArtifacts: Bool = true
) throws {
  if url.resolvingSymlinksInPath().path.hasPrefix("/nix/store/") {
    throw CLIError("This policy is managed by Nix; change programs.pared.features and reactivate")
  }
  let directory = url.deletingLastPathComponent()
  let profileURL = directory.appendingPathComponent(Artifacts.profileFilename)
  let declarationsURL = directory.appendingPathComponent(Artifacts.declarationsFilename)
  // The two generated destinations need no heap-backed collection
  let generatedURLs: InlineArray<2, URL> = [profileURL, declarationsURL]
  let policyURL = url.standardizedFileURL.resolvingSymlinksInPath()
  guard
    !generatedURLs.indices.contains(where: {
      generatedURLs[$0].standardizedFileURL.resolvingSymlinksInPath() == policyURL
    })
  else {
    throw CLIError("The policy path conflicts with a generated artifact; choose another filename")
  }
  try policy.save(url)
  try profileData(policy: policy, catalog: catalog).write(to: profileURL, options: .atomic)
  try declarationData(policy: policy, catalog: catalog).write(
    to: declarationsURL, options: .atomic)
  if reportArtifacts {
    report("Saved policy: \(url.path)")
    report("Install the updated profile for managed controls: \(profileURL.path)")
    report("MDM declarations: \(declarationsURL.path)")
  }
  try applyPreferences(policy: policy, catalog: catalog, names: names, reset: reset)
  if reportArtifacts {
    report(
      "Relaunch affected apps or log in again. Models may need downloading. Nix-managed settings must also be changed in Nix."
    )
  }
}
