import Foundation

private let allFeaturesArgument = "all"

private let usage = """
  Usage: pared <command> [subcommand] [features...] [--policy FILE] [--dry-run]

  \(Command.help)

  Feature states: enabled, disabled, unmanaged. A missing policy defaults to disabled.
  Local policy: ~/Library/Application Support/pared/policy.json
  Enable/disable never delete models. Cleanup is explicit; install the profile to block model downloads.
  Management artifacts need installation; enabled permits a feature, not provisioning.
  --policy FILE selects an existing policy; --dry-run previews without writing.
  Reset restores Apple defaults, not previous values; replace the profile too.
  Profile status exits 0 when installed, 1 when absent; query failures are errors.
  Models status is a downloaded snapshot, not live progress; errors exit 1.
  Models download requires a catalog recovery mapping; callbacks mean acceptance.
  """

private struct Status: Encodable {
  let desired: FeatureState
  let preferences: [PreferenceStatus]
  let managementRequired: Bool
  let modelAvailabilityOnly: Bool
}

func runCLI(_ arguments: [String]) throws -> ExitStatus {
  if arguments.isEmpty || CLIOption.isHelp(arguments[...]) {
    print(usage)
    return .success
  }
  if let group = arguments.first {
    let children = Command.subcommands(for: group)
    if !children.isEmpty
      && (arguments.count == 1 || CLIOption.isHelp(arguments.dropFirst()))
    {
      print(
        "Usage: pared <command> [arguments]\n\n"
          + children.map { "  " + $0.rawValue }.joined(separator: "\n"))
      return .success
    }
  }
  var args = arguments[...]
  let command = try Command.parse(&args)
  if CLIOption.isHelp(args) {
    print(usage)
    return .success
  }
  let catalog = try Catalog.load()
  var url = Policy.defaultURL
  var explicit = false
  var dryRun = false
  var names: [String] = []
  while let arg = args.popFirst() {
    switch CLIOption(rawValue: arg) {
    case .policy:
      guard !explicit, let path = args.popFirst(), !path.hasPrefix("-") else {
        throw CLIError("--policy requires one file path")
      }
      url = URL(fileURLWithPath: path)
      explicit = true
    case .dryRun: dryRun = true
    default:
      guard !arg.hasPrefix("-") else { throw CLIError("Unknown option: \(arg)") }
      names.append(arg)
    }
  }
  if names.contains(allFeaturesArgument) {
    guard names == [allFeaturesArgument] else { throw CLIError("Use 'all' alone") }
    names = catalog.features.keys.sorted()
  }
  for name in names where catalog.features[name] == nil {
    throw CLIError("Unknown feature: \(name)")
  }
  if !command.acceptsFeatures && !names.isEmpty {
    throw CLIError("\(command.rawValue) does not accept feature arguments")
  }
  if dryRun && !command.acceptsDryRun {
    throw CLIError("--dry-run does not apply to \(command.rawValue)")
  }
  if command == .features {
    for (name, feature) in catalog.features.sorted(by: { $0.key < $1.key }) {
      var controls: [String] = []
      if !feature.preferences.isEmpty { controls.append("preferences") }
      if !feature.restrictions.isEmpty || !feature.assetSets.isEmpty { controls.append("profile") }
      if !feature.declarations.isEmpty { controls.append("MDM") }
      if !feature.assetSets.isEmpty { controls.append("models") }
      print("\(name): \(feature.description) [\(controls.joined(separator: ", "))]")
    }
    return .success
  }
  if command == .check { return checkService(catalog: catalog) }
  var policy = try Policy.load(url, explicit: explicit, catalog: catalog)
  if let state = command.desiredState {
    guard !names.isEmpty else {
      throw CLIError("\(command.rawValue) requires feature names or 'all'")
    }
    for name in names {
      policy.features[name] = state
    }
  }
  let selected = names.isEmpty ? catalog.features.keys.sorted() : Set(names).sorted()
  switch command {
  case .status:
    let status = Dictionary(
      uniqueKeysWithValues: selected.map { name in
        let feature = catalog.features[name]!
        return (
          name,
          Status(
            desired: policy.state(name), preferences: feature.preferences.map(preferenceStatus),
            managementRequired: !feature.restrictions.isEmpty || !feature.declarations.isEmpty
              || !feature.assetSets.isEmpty,
            modelAvailabilityOnly: feature.preferences.isEmpty && feature.restrictions.isEmpty
              && feature.declarations.isEmpty)
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
    let targets = Set(selected.flatMap { catalog.features[$0]!.assetSets }).sorted()
    let statuses = try modelStatus(targets, catalog: catalog)
    FileHandle.standardOutput.write(try jsonData(statuses))
    return statuses.contains { $0.queryError != nil || $0.inventoryError != nil }
      ? .failure : .success
  case .cleanup:
    let requested = Set(selected.flatMap { catalog.features[$0]!.assetSets })
    let targets = policy.cleanupTargets(catalog).filter { requested.contains($0) }
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
    if url.resolvingSymlinksInPath().path.hasPrefix("/nix/store/") {
      throw CLIError("This policy is managed by Nix; change programs.pared.features and reactivate")
    }
    let directory = url.deletingLastPathComponent()
    let profileURL = directory.appendingPathComponent(Artifacts.profileFilename)
    let declarationsURL = directory.appendingPathComponent(Artifacts.declarationsFilename)
    guard
      ![profileURL, declarationsURL].contains(where: {
        $0.standardizedFileURL.resolvingSymlinksInPath()
          == url.standardizedFileURL.resolvingSymlinksInPath()
      })
    else {
      throw CLIError("The policy path conflicts with a generated artifact; choose another filename")
    }
    try policy.save(url)
    try profileData(policy: policy, catalog: catalog).write(to: profileURL, options: .atomic)
    try declarationData(policy: policy, catalog: catalog).write(
      to: declarationsURL, options: .atomic)
    report("Saved policy: \(url.path)")
    report("Install the updated profile for managed controls: \(profileURL.path)")
    report("MDM declarations: \(declarationsURL.path)")
    try applyPreferences(
      policy: policy, catalog: catalog, names: selected, reset: command == .reset)
    report(
      "Relaunch affected apps or log in again. Models may need downloading. Nix-managed settings must also be changed in Nix."
    )
  case .features, .check:
    preconditionFailure("Handled before policy loading")
  }
  return .success
}
