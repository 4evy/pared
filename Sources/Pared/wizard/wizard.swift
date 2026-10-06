import Darwin
import Foundation
import Noora

private enum WizardAction: String, CaseIterable, CustomStringConvertible {
  case install = "Install Pared or set up the terminal command"
  case configure = "Choose which Apple Intelligence features to manage"
  case status = "View the desired feature policy"
  case profile = "Open configuration profile installation"
  case cleanup = "Preview or remove downloaded models"
  case finish = "Finish"

  var description: String { rawValue }
}

private enum WizardFeatureChange: String, CaseIterable, CustomStringConvertible {
  case disableAll = "Disable every feature"
  case enable = "Enable selected features"
  case disable = "Disable selected features"
  case reset = "Stop managing selected features"
  case back = "Back to the main menu"

  var description: String { rawValue }

  var state: FeatureState {
    switch self {
    case .enable: .enabled
    case .disable, .disableAll: .disabled
    case .reset: .unmanaged
    case .back: preconditionFailure("Back does not change policy")
    }
  }
}

private struct WizardFeature: Equatable, CustomStringConvertible {
  let name: String
  let description: String
}

private let wizardUsage = """
  Usage: pared wizard [--prefix DIR] [--policy FILE]

  Open an interactive menu to install Pared, choose feature settings, open
  profile installation, and preview or remove models. Nothing changes until
  you confirm an action. Use arrow keys to move and Enter to select.

  --prefix DIR   Suggested installation directory (default: ~/.local)
  --policy FILE  Read an existing policy, just like other Pared commands
  --help, -h     Show this help without opening the wizard

  Installing the command does not change feature settings or remove models.
  Profile installation still requires your approval in System Settings.
  """

func runWizard(_ arguments: ArraySlice<String>) throws -> ExitStatus {
  if CLIOption.isHelp(arguments) {
    print(wizardUsage)
    return .success
  }
  var args = arguments
  var prefix: URL?
  var policyURL: URL?
  while let option = args.popFirst() {
    guard option == "--prefix" || option == "--policy" else {
      throw CLIError("Unknown wizard option: \(option). Run pared wizard --help.")
    }
    guard let value = args.popFirst(), !value.isEmpty, !value.hasPrefix("-") else {
      throw CLIError("\(option) requires a path")
    }
    if option == "--prefix" {
      guard prefix == nil else { throw CLIError("Use --prefix only once") }
      prefix = try wizardPrefix(value)
    } else {
      guard policyURL == nil else { throw CLIError("Use --policy only once") }
      policyURL = URL(fileURLWithPath: value)
    }
  }
  guard Terminal.isInteractive(), isatty(STDOUT_FILENO) != 0 else {
    throw CLIError(
      "The wizard needs a terminal. Run pared wizard in a terminal, or use pared --help for non-interactive commands."
    )
  }
  guard geteuid() != 0 else {
    throw CLIError("Run the wizard as your normal user, without sudo")
  }
  let catalog = try Catalog.load()
  var wizard = Wizard(
    ui: Noora(), catalog: catalog, policyURL: policyURL ?? Policy.defaultURL,
    explicitPolicy: policyURL != nil,
    prefix: prefix
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local"))
  return wizard.run()
}

private func wizardPrefix(_ input: String) throws(CLIError) -> URL {
  let path = (input as NSString).expandingTildeInPath
  guard path.hasPrefix("/"), path.rangeOfCharacter(from: .controlCharacters) == nil else {
    throw CLIError("Use a full installation path, such as ~/.local or /Users/you/.local")
  }
  return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
}

private struct Wizard {
  let ui: Noora
  let catalog: Catalog
  let policyURL: URL
  let explicitPolicy: Bool
  var prefix: URL

  mutating func run() -> ExitStatus {
    ui.info(
      .alert(
        "Welcome to Pared",
        takeaways: [
          "No developer tools or administrator password are needed.",
          "Choose an action below. Opening this menu changes nothing.",
          "SIP stays enabled. Profile installation is reviewed in System Settings.",
        ]))
    var result = ExitStatus.success
    while true {
      let action: WizardAction = ui.singleChoicePrompt(
        title: "Pared wizard", question: "What would you like to do?")
      do {
        switch action {
        case .install: try install()
        case .configure: try configure()
        case .status: try showPolicy()
        case .profile: try openProfile()
        case .cleanup:
          let cleanupResult = try cleanup()
          if cleanupResult != .success { result = cleanupResult }
        case .finish: return result
        }
      } catch {
        ui.error(
          .alert(
            "\(error)",
            takeaways: [
              "The action did not finish. Earlier writes or requests may have succeeded.",
              "You can choose another action or finish; nothing is retried automatically.",
            ]))
        result = .failure
      }
    }
  }

  private func policy() throws -> Policy {
    try Policy.load(policyURL, explicit: explicitPolicy, catalog: catalog)
  }

  private mutating func install() throws {
    while true {
      let path = ui.textPrompt(
        title: "Install Pared", prompt: "Where should Pared be installed?",
        description: "Press Enter to keep the suggested directory. No sudo is needed.",
        defaultValue: prefix.path)
      do {
        prefix = try wizardPrefix(path)
        break
      } catch {
        ui.error(.alert("\(error)"))
      }
    }
    guard
      ui.yesOrNoChoicePrompt(
        question: "Install Pared in \(prefix.path)?", defaultAnswer: false,
        description:
          "A previous wizard installation here will be replaced. Your policy will not change.")
    else { return }
    let command = try WizardInstallation.install(prefix: prefix)
    ui.success(.alert("Pared is installed at \(command.path)"))
    let binDirectory = command.deletingLastPathComponent()
    let environment = ProcessInfo.processInfo.environment
    let isOnPath = environment["PATH", default: ""].split(separator: ":").contains {
      String($0) == binDirectory.path
    }
    if !isOnPath {
      if let profile = WizardInstallation.shellProfile(environment: environment),
        ui.yesOrNoChoicePrompt(
          question: "Add Pared to your terminal's PATH?", defaultAnswer: false,
          description:
            "This appends a PATH entry to \(profile.path). Open a new terminal afterward.")
      {
        try WizardInstallation.addToPath(binDirectory: binDirectory, profile: profile)
        ui.success("Open a new terminal window, then run pared wizard")
      } else {
        ui.info(
          .alert(
            "Shell configuration was not changed",
            takeaways: [
              "Use the full path: \(command.path)"
            ]))
      }
    }
  }

  private func showPolicy() throws {
    let policy = try policy()
    ui.table(
      headers: ["Feature", "Desired state"],
      rows: catalog.features.keys.sorted().map { [$0, policy.state($0).rawValue] })
    ui.info(
      .alert(
        "Policy: \(policyURL.path)",
        takeaways: [
          "Desired policy is not proof of runtime enforcement.",
          "Use pared status to inspect observed preferences as well.",
        ]))
  }

  private func configure() throws {
    var policy = try policy()
    let change: WizardFeatureChange = ui.singleChoicePrompt(
      title: "Feature settings", question: "How should Pared manage features?",
      description:
        "Enable allows use, disable blocks use, and stop managing removes local preference overrides."
    )
    guard change != .back else { return }
    let names: [String]
    if change == .disableAll {
      names = catalog.features.keys.sorted()
    } else {
      let options = catalog.features.sorted(by: { $0.key < $1.key }).map { name, feature in
        WizardFeature(
          name: name,
          description: "\(name): \(feature.description) [\(policy.state(name).rawValue)]")
      }
      let selected = ui.multipleChoicePrompt(
        title: "Choose features", question: "Which features should change?", options: options,
        description:
          "Space selects a feature; Enter continues. Selecting none returns without changes.",
        filterMode: .toggleable)
      names = selected.map(\.name).sorted()
    }
    guard !names.isEmpty else { return }
    let isNew = !FileManager.default.fileExists(atPath: policyURL.path)
    if isNew {
      ui.warning(
        .alert(
          "A new policy defaults every feature to disabled",
          takeaway:
            "Unselected features also remain disabled in the generated profile. Review the policy before installing it."
        ))
    }
    ui.info(
      .alert(
        "Set these features to \(change.state.rawValue)",
        takeaways:
          names.map { TerminalText(stringLiteral: $0) }))
    guard
      ui.yesOrNoChoicePrompt(
        question: "Save this policy and apply the selected local preferences?",
        defaultAnswer: false,
        description:
          "This does not remove or download models. Replace the profile to change enforced controls. Stop managing does not restore old values."
      )
    else { return }
    for name in names { policy.features[name] = change.state }
    try persistPolicyChanges(
      policy: policy, url: policyURL, catalog: catalog, names: names, reset: change == .reset)
    ui.success(
      .alert(
        "Saved feature policy",
        takeaways: [
          "Next, choose profile installation and complete the review in System Settings.",
          "Relaunch affected apps or log in again for local preferences to take effect.",
        ]))
  }

  private func requireSavedPolicy() throws {
    guard FileManager.default.fileExists(atPath: policyURL.path) else {
      throw CLIError("No saved policy exists at \(policyURL.path). Choose feature settings first.")
    }
  }

  private func openProfile() throws {
    try requireSavedPolicy()
    let policy = try policy()
    guard
      ui.yesOrNoChoicePrompt(
        question: "Generate the profile and open System Settings?", defaultAnswer: false,
        description:
          "Review and install it yourself. An existing profile stays enforced until replaced; opening the file does not install it."
      )
    else { return }
    try openProfileInstallation(policy: policy, catalog: catalog)
    ui.info(
      .alert(
        "Finish profile installation in System Settings",
        takeaways: [
          "Run pared profile status afterward. Profile presence does not prove enforcement."
        ]))
  }

  private func cleanup() throws -> ExitStatus {
    try requireSavedPolicy()
    let policy = try policy()
    let targets = policy.cleanupTargets(catalog)
    guard !targets.isEmpty else {
      ui.info("No model sets are eligible for cleanup; no requests were sent")
      return .success
    }
    ui.info(
      .alert(
        "Cleanup preview: eligible model sets",
        takeaways:
          targets.map { TerminalText(stringLiteral: $0) }))
    ui.warning(
      .alert(
        "This is eligibility, not a disk-space estimate",
        takeaway:
          "Only sets with every known consumer disabled are selected. Install the matching profile to block future downloads. Removing models also cancels their Pared download requests."
      ))
    guard
      ui.yesOrNoChoicePrompt(
        question: "Remove these downloaded model sets now?", defaultAnswer: false,
        description:
          "This requests deletion from Apple's service. Enabled or unmanaged shared consumers are protected. Choose No to keep this as a preview."
      )
    else {
      ui.info("Preview only; no model requests were sent")
      return .success
    }
    let result = resetModels(targets, catalog: catalog)
    if result == .success {
      ui.info("Apple's service returned successfully. This does not measure reclaimed disk space.")
    } else {
      ui.error(
        .alert(
          "Cleanup did not report success (exit \(result.rawValue))",
          takeaways: [
            "Partial removal or an unknown request outcome is possible. Inspect the diagnostics above before trying again."
          ]))
    }
    return result
  }
}
