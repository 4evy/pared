import Darwin
import Foundation
import Noora

private enum WizardAction: String, CaseIterable, CustomStringConvertible {
  case setup = "Guided setup (start here)"
  case configure = "Change feature settings"
  case status = "Review saved settings"
  case profile = "Apply settings in System Settings"
  case cleanup = "Review downloaded models"
  case install = "Install the Pared command"
  case finish = "Finish"

  var description: String { rawValue }
}

private enum WizardStepAction: String, CaseIterable, CustomStringConvertible {
  case next = "Continue"
  case skip = "Skip this step"
  case back = "Return to the main menu"

  var description: String { rawValue }
}

private enum WizardSetupStep: String, CaseIterable {
  case features = "Choose features"
  case profile = "Apply settings"
  case models = "Downloaded models"
  case command = "Pared command"

  var detail: String {
    switch self {
    case .features: "Decide what you want on or off, then review before saving."
    case .profile:
      "A configuration profile tells macOS which features to allow. You install it in System Settings."
    case .models:
      "Review models that your turned-off features no longer need. Removal is optional."
    case .command: "Optional: install Pared so you can use it from any terminal."
    }
  }

  var requiresSavedPolicy: Bool { self == .profile || self == .models }
}

private enum WizardPageAction: String, CustomStringConvertible {
  case next = "Next page"
  case previous = "Previous page"
  case done = "Done reviewing"

  var description: String { rawValue }
}

private enum WizardReviewAction: String, CaseIterable, CustomStringConvertible {
  case edit = "Change more features"
  case save = "Continue to save"
  case cancel = "Discard changes and return"

  var description: String { rawValue }
}

private enum WizardFeatureChange: String, CaseIterable, CustomStringConvertible {
  case disableAll = "Turn everything off"
  case enable = "Turn on selected features"
  case disable = "Turn off selected features"
  case reset = "Let macOS manage selected features"
  case back = "Discard changes and return"

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

private struct WizardPrefixRule: ValidatableRule {
  let error: ValidatableError =
    "Use a full installation path, such as ~/.local or /Users/you/.local"

  func validate(input: String) -> Bool { (try? wizardPrefix(input)) != nil }
}

@MainActor
func runWizard(prefix: URL?, policyURL: URL?) async throws -> ExitStatus {
  guard Terminal.isInteractive(), isatty(STDOUT_FILENO) != 0 else {
    throw CLIError(
      "The wizard needs a terminal. Run pared wizard in a terminal, or use pared --help for non-interactive commands."
    )
  }
  guard geteuid() != 0 else {
    throw CLIError("Run the wizard as your normal user, without sudo")
  }
  if let size = Terminal(signalBehavior: .none).size(), size.columns < 40 || size.rows < 16 {
    throw CLIError(
      "Make your terminal at least 40 columns wide and 16 rows tall, then run pared wizard again")
  }
  let catalog = try Catalog.load()
  var wizard = Wizard(
    ui: Noora(theme: WizardStyle.theme, content: WizardStyle.content, terminal: WizardTerminal()),
    catalog: catalog,
    policyURL: policyURL ?? Policy.defaultURL,
    prefix: prefix
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local"))
  return await wizard.run()
}

func wizardPrefix(_ input: String) throws(CLIError) -> URL {
  let path = (input as NSString).expandingTildeInPath
  guard path.hasPrefix("/"), path.rangeOfCharacter(from: .controlCharacters) == nil else {
    throw CLIError("Use a full installation path, such as ~/.local or /Users/you/.local")
  }
  return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
}

@MainActor
private struct Wizard {
  let ui: Noora
  let catalog: Catalog
  let policyURL: URL
  var prefix: URL

  mutating func run() async -> ExitStatus {
    panel(
      "\(.primary("Welcome to Pared"))",
      lines: [
        "Choose which Apple Intelligence features you want on your Mac.",
        "You review and confirm before anything changes.",
      ])
    var result = ExitStatus.success
    while true {
      let action: WizardAction = ui.singleChoicePrompt(
        title: "Pared", question: "What would you like to do?",
        description: hasSavedPolicy
          ? "Your settings are saved. Apply them in System Settings after making changes."
          : "First time here? Choose guided setup. You can skip any step.",
        renderer: WizardRenderer()
      )
      do {
        switch action {
        case .setup:
          let setupResult = try await guidedSetup()
          if setupResult != .success { result = setupResult }
        case .install: _ = try await install()
        case .configure: _ = try configure()
        case .status: try showPolicy()
        case .profile: _ = try openProfile()
        case .cleanup:
          let cleanupResult = try cleanup()
          if cleanupResult.status != .success { result = cleanupResult.status }
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

  private var hasSavedPolicy: Bool {
    FileManager.default.fileExists(atPath: policyURL.path)
  }

  private func policy() throws -> Policy {
    // An explicit wizard path can be a new policy destination
    try Policy.load(policyURL, explicit: false, catalog: catalog)
  }

  private mutating func guidedSetup() async throws -> ExitStatus {
    let steps = WizardSetupStep.allCases
    var summary: [TerminalText] = []
    var result = ExitStatus.success
    for (index, step) in steps.enumerated() {
      if step.requiresSavedPolicy && !hasSavedPolicy {
        summary.append("\(step.rawValue): skipped because no policy was saved")
        continue
      }
      let action: WizardStepAction = ui.singleChoicePrompt(
        title: "Setup \(index + 1) of \(steps.count): \(step.rawValue)",
        question: "Ready for this step?",
        description: "\(step.detail) Returning to the menu keeps any completed actions.",
        renderer: WizardRenderer())
      switch action {
      case .back:
        ui.info(
          .alert(
            "Setup paused", takeaways: summary + ["Choose guided setup again to revisit any step."])
        )
        return result
      case .skip:
        summary.append("\(step.rawValue): skipped")
        continue
      case .next: break
      }
      switch step {
      case .features:
        summary.append(try configure() ? "Features: saved" : "Features: unchanged")
      case .profile:
        summary.append(
          try openProfile()
            ? "Profile: opened; finish installation in System Settings" : "Profile: not opened")
      case .models:
        let cleanupResult = try cleanup()
        if cleanupResult.status != .success { result = cleanupResult.status }
        summary.append(
          cleanupResult.requested
            ? (cleanupResult.status == .success
              ? "Models: removal requested" : "Models: removal needs attention")
            : "Models: kept")
      case .command:
        summary.append(
          try await install() ? "Pared command: installed" : "Pared command: unchanged")
      }

    }
    panel(
      "\(.primary("Setup summary"))",
      lines: summary + [
        "If you opened a profile, finish installing it in System Settings."
      ])
    return result
  }

  private mutating func install() async throws -> Bool {
    let path = ui.textPrompt(
      title: "Install Pared", prompt: "Where should Pared be installed?",
      description: "Press Enter to keep the suggested directory. No sudo is needed.",
      defaultValue: prefix.path, renderer: WizardRenderer(), validationRules: [WizardPrefixRule()])
    prefix = try wizardPrefix(path)
    guard
      ui.yesOrNoChoicePrompt(
        question: "Install Pared here?", defaultAnswer: false,
        description:
          "Directory: \(prefix.path)\nReplaces a previous Pared installation here. Your feature settings stay unchanged.",
        renderer: WizardRenderer())
    else {
      ui.info("Installation cancelled; no files were changed")
      return false
    }
    let installPrefix = prefix
    let command = try await ui.progressStep(
      message: "Copying and verifying Pared", successMessage: nil, errorMessage: nil,
      showSpinner: true, renderer: WizardRenderer()
    ) { @Sendable _ in
      try await WizardInstallation.install(prefix: installPrefix)
    }
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
            "This appends a PATH entry to \(profile.path). Open a new terminal afterward.",
          renderer: WizardRenderer())
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
    return true
  }

  private func showPolicy() throws {
    let saved = try policy()
    reviewSettings(saved, original: nil, touched: [])
    panel(
      "Saved settings",
      lines: [
        hasSavedPolicy ? "File: \(policyURL.path)" : "Preview only; no settings have been saved.",
        "These are your choices, not a check of what macOS is enforcing.",
        "Use pared status to inspect local settings.",
      ])
  }

  private var featureNames: [String] {
    catalog.presentations
      .sorted(
        using: KeyPathComparator(
          \.wizardTitle, comparator: String.StandardComparator.localizedStandard)
      )
      .map(\.id)
  }

  private func featureName(_ name: String) -> String {
    catalog.presentation(name).wizardTitle
  }

  private func panel(_ title: TerminalText, lines: [TerminalText]) {
    let terminal = Terminal(signalBehavior: .none)
    let content = ([title] + lines).map {
      $0.formatted(theme: WizardStyle.theme, terminal: terminal)
    }.joined(separator: "\n")
    WizardRenderer().render(content, standardPipeline: StandardOutputPipeline())
  }

  private func configure() throws -> Bool {
    let original = try policy()
    var draft = original
    var touched = Set<String>()
    let isNew = !hasSavedPolicy
    if isNew {
      panel(
        "\(.accent("New setup: everything starts off"))",
        lines: [
          "Turn on the features you want. Everything else stays off.",
          "You will review all settings before saving.",
        ])
    }
    while true {
      let change: WizardFeatureChange = ui.singleChoicePrompt(
        title: "Feature settings", question: "What would you like to change?",
        description:
          "On allows a feature; Off blocks it. Leave alone removes Pared controls, including selected local overrides.",
        renderer: WizardRenderer()
      )
      guard change != .back else {
        ui.info("Draft discarded; policy and preferences were not changed")
        return false
      }
      let names: [String]
      if change == .disableAll {
        names = catalog.featureNames
      } else {
        names = wizardSelectFeatures(
          options: featureNames.map { (id: $0, label: featureName($0)) }
        ).sorted()
      }
      draft.set(change.state, for: names)
      touched.formUnion(names)
      guard !touched.isEmpty else { continue }

      reviewSettings(draft, original: original, touched: touched)
      let targets = draft.cleanupTargets(catalog)
      panel(
        "\(.primary("Ready to save?"))",
        lines: [
          "\(touched.count) selected features. Saving removes no models.",
          "\(targets.count) model groups can be reviewed in the cleanup step.",
          "Next: apply your settings in System Settings.",
          "Leave alone removes overrides; it does not restore previous values.",
        ])
      let review: WizardReviewAction = ui.singleChoicePrompt(
        question: "What would you like to do with this draft?", renderer: WizardRenderer())
      switch review {
      case .edit: continue
      case .cancel:
        ui.info("Draft discarded; policy and preferences were not changed")
        return false
      case .save: break
      }
      guard
        ui.yesOrNoChoicePrompt(
          question: "Save these settings?",
          defaultAnswer: false,
          description:
            "Saves your choices and updates selected local settings. You apply the profile and remove models separately.",
          renderer: WizardRenderer()
        )
      else {
        ui.info("Save cancelled; your draft is still available to edit")
        continue
      }
      break
    }
    let names = touched.sorted()
    let managed = names.filter { draft.state($0) != .unmanaged }
    let unmanaged = names.filter { draft.state($0) == .unmanaged }
    try verifyPolicyUnchanged(original, exists: !isNew)
    // Mixed drafts apply desired values and remove overrides separately
    try persistPolicyChanges(
      policy: draft, url: policyURL, catalog: catalog, names: managed, reset: false,
      reportArtifacts: false)
    try applyPreferences(policy: draft, catalog: catalog, names: unmanaged, reset: true)
    ui.success(
      .alert(
        "Your settings are saved",
        takeaways: [
          "Next: choose Apply settings in System Settings to install the matching profile.",
          "Relaunch affected apps or log in again for local preferences to take effect.",
        ]))
    return true
  }

  private func reviewSettings(_ settings: Policy, original: Policy?, touched: Set<String>) {
    // Each page fits the terminal; changed entries come first and keep their
    // text marker when color is disabled
    let names =
      featureNames.filter { touched.contains($0) }
      + featureNames.filter { !touched.contains($0) }
    let rows = Terminal(signalBehavior: .none).size()?.rows ?? 24
    let count = max(1, min(5, (rows - 12) / 3))
    let pages = stride(from: 0, to: names.count, by: count).map {
      Array(names[$0..<min($0 + count, names.count)])
    }
    var page = 0
    let renderer = WizardRenderer()
    while !pages.isEmpty {
      var lines: [TerminalText] = []
      for name in pages[page] {
        let feature = catalog.features[name]!
        let changed = original.map { $0.state(name) != settings.state(name) } ?? false
        let label = featureName(name)
        let value = settings.state(name).wizardTitle
        let transition = original.map { "\($0.state(name).wizardTitle) → \(value)" } ?? value
        lines.append(changed ? "  * \(.primary(label))" : "    \(label)")
        lines.append(changed ? "    \(.primary(transition))" : "    \(.muted(transition))")
        if feature.modelAvailabilityOnly {
          lines.append("    Models only; app settings unchanged")
        } else if touched.contains(name) && !feature.preferences.isEmpty {
          lines.append(
            settings.state(name) == .unmanaged
              ? "    Local override: remove" : "    Local setting: apply")
        }
      }
      var options: [WizardPageAction] = []
      if page < pages.count - 1 {
        options.append(.next)
      } else {
        options.append(.done)
      }
      if page > 0 { options.append(.previous) }
      if page < pages.count - 1 { options.append(.done) }
      let content = lines.map {
        $0.formatted(theme: WizardStyle.theme, terminal: Terminal(signalBehavior: .none))
      }.joined(separator: "\n")
      let action = ui.singleChoicePrompt(
        title:
          "\(original == nil ? (hasSavedPolicy ? "Saved settings" : "Default settings") : "Review changes") · \(page + 1)/\(pages.count)",
        question: original == nil ? "Your chosen settings" : "* marks a changed setting",
        options: options, description: TerminalText(stringLiteral: String(content.dropFirst(2))),
        autoselectSingleChoice: false, renderer: renderer)
      switch action {
      case .next: page += 1
      case .previous: page -= 1
      case .done: return
      }
    }
  }

  private func requireSavedPolicy() throws {
    guard hasSavedPolicy else {
      throw CLIError("No saved policy exists at \(policyURL.path). Choose feature settings first.")
    }
  }

  private func verifyPolicyUnchanged(_ expected: Policy, exists: Bool = true) throws {
    guard hasSavedPolicy == exists, try policy() == expected else {
      throw CLIError("The policy changed while you were reviewing it. Review the settings again.")
    }
  }

  private func openProfile() throws -> Bool {
    try requireSavedPolicy()
    let policy = try policy()
    guard
      ui.yesOrNoChoicePrompt(
        question: "Open the profile in System Settings?", defaultAnswer: false,
        description:
          "Review the profile there, then install it. Opening it does not apply changes; an older profile stays active until replaced.",
        renderer: WizardRenderer()
      )
    else { return false }
    try verifyPolicyUnchanged(policy)
    try openProfileInstallation(policy: policy, catalog: catalog)
    ui.info(
      .alert(
        "Finish profile installation in System Settings",
        takeaways: [
          "Run pared profile status afterward. Profile presence does not prove enforcement."
        ]))
    return true
  }

  private func cleanup() throws -> (status: ExitStatus, requested: Bool) {
    try requireSavedPolicy()
    let policy = try policy()
    let targets = policy.cleanupTargets(catalog)
    guard !targets.isEmpty else {
      ui.info("No model sets are eligible for cleanup; no requests were sent")
      return (.success, false)
    }
    panel(
      "\(.primary("Models eligible for removal"))",
      lines:
        targets.map { TerminalText(stringLiteral: "• " + catalog.modelTitle($0, wizard: true)) } + [
          "This list uses your settings; it does not check downloads or sizes."
        ])
    panel(
      "\(.accent("Removal is optional"))",
      lines: [
        "Only models whose known features are all off are listed.",
        "Apply your settings first to block future downloads.",
        "Removal also cancels Pared download requests.",
      ])
    guard
      ui.yesOrNoChoicePrompt(
        question: "\(.danger("Remove these downloaded models?"))", defaultAnswer: false,
        description:
          "Asks macOS to delete the listed models. Models shared with On or Leave alone features are kept. Choose No to keep everything.",
        renderer: WizardRenderer()
      )
    else {
      ui.info("Preview only; no model requests were sent")
      return (.success, false)
    }
    try verifyPolicyUnchanged(policy)
    let result = resetModels(targets, catalog: catalog)
    if result == .success {
      ui.info(
        "No model folders remain for the selected sets. Reclaimed disk space was not measured.")
    } else {
      ui.error(
        .alert(
          "Cleanup did not report success (exit \(result.rawValue))",
          takeaways: [
            "Partial removal or an unknown request outcome is possible. Inspect the diagnostics above before trying again."
          ]))
    }
    return (result, true)
  }
}
