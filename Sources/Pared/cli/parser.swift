import ArgumentParser
import Foundation

struct ParedCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pared",
    abstract: "Manage Apple Intelligence features, configuration profiles, and downloaded models",
    discussion: """
      Policy: ~/Library/Application Support/pared/policy.json
      A new policy disables every feature. Use --policy FILE to read an existing policy.
      Use --dry-run with supported commands to preview changes without writing.

      enable/disable save settings; they do not remove or download models.
      Install the generated profile in System Settings to enforce managed controls
      and block downloads. Replace it after changing policy, including after reset.
      reset removes local preferences; it does not restore their previous values.
      Siri voice activation is separate: enable siriVoiceTrigger if you want it.
      Siri services can remain running when Siri is disabled.
      """,
    subcommands: [
      GUICommand.self, WizardCommand.self, FeaturesCommand.self, StatusCommand.self,
      EnableCommand.self, DisableCommand.self, ResetCommand.self, ApplyCommand.self,
      ProfileCommand.self, DeclarationsCommand.self, ModelsCommand.self,
    ])
}

struct PolicyOptions: ParsableArguments {
  @Option(
    name: .customLong("policy"),
    help: ArgumentHelp("Read an existing policy", valueName: "file"),
    completion: .file(),
    transform: { path in
      guard !path.isEmpty else { throw ValidationError("--policy requires a file path") }
      return URL(fileURLWithPath: path)
    })
  var url: URL?
}

extension CompletionKind {
  fileprivate static var features: CompletionKind {
    .custom { _, _, _ in
      (try? Catalog.load().featureNames).map { ["all"] + $0 } ?? ["all"]
    }
  }
}

private protocol PolicyCommand: ParsableCommand {
  static var operation: Command { get }
  static var abstract: String { get }
  var options: PolicyOptions { get }
  var features: [String] { get }
  var dryRun: Bool { get }
}

extension PolicyCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: operation.commandName,
      abstract: abstract)
  }

  var features: [String] { [] }
  var dryRun: Bool { false }

  mutating func run() throws {
    let status = try executeCommand(
      Self.operation, names: features, policyURL: options.url, dryRun: dryRun)
    if status != .success { throw ExitCode(status.rawValue) }
  }
}

private struct FeaturesCommand: PolicyCommand {
  static let operation = Command.features
  static let abstract = "List feature names and their preference, profile, and model controls"
  @OptionGroup var options: PolicyOptions
}

private struct StatusCommand: PolicyCommand {
  static let operation = Command.status
  static let abstract = "Show desired policy and observed preferences as JSON"
  @OptionGroup var options: PolicyOptions
  @Argument(help: "Feature names or 'all'; omit to inspect every feature", completion: .features)
  var features: [String] = []
}

private struct FeatureChangeOptions: ParsableArguments {
  @OptionGroup var policy: PolicyOptions
  @Argument(help: "Feature names or 'all'", completion: .features) var features: [String]
  @Flag(help: "Preview the policy without writing") var dryRun = false
}

private protocol FeatureChangeCommand: PolicyCommand {
  var change: FeatureChangeOptions { get }
}

extension FeatureChangeCommand {
  var options: PolicyOptions { change.policy }
  var features: [String] { change.features }
  var dryRun: Bool { change.dryRun }
}

private struct EnableCommand: FeatureChangeCommand {
  static let operation = Command.enable
  static let abstract = "Enable features; save policy, profile, and MDM declarations"
  @OptionGroup var change: FeatureChangeOptions
}

private struct DisableCommand: FeatureChangeCommand {
  static let operation = Command.disable
  static let abstract = "Disable features; save policy, profile, and MDM declarations"
  @OptionGroup var change: FeatureChangeOptions
}

private struct ResetCommand: FeatureChangeCommand {
  static let operation = Command.reset
  static let abstract = "Remove local preferences; mark features unmanaged"
  @OptionGroup var change: FeatureChangeOptions
}

private struct ApplyCommand: PolicyCommand {
  static let operation = Command.apply
  static let abstract = "Apply policy preferences; save profile and MDM declarations"
  @OptionGroup var options: PolicyOptions
  @Flag(help: "Preview the policy without writing") var dryRun = false
}

private struct DeclarationsCommand: PolicyCommand {
  static let operation = Command.declarations
  static let abstract = "Print macOS 27 MDM configuration declarations"
  @OptionGroup var options: PolicyOptions
}

private struct ProfileCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "profile", abstract: "Generate or inspect configuration profiles",
    discussion: """
      Profile status reports installed metadata, not enforced settings.
      It exits 0 when installed and 1 when absent; query failures are errors.
      Apple deprecated the legacy AI restrictions in macOS 26.4.
      Their MDM replacements require supervised enrollment. Local profiles still
      supply forced preferences and model download blocks.
      """,
    subcommands: [ProfileShowCommand.self, ProfileOpenCommand.self, ProfileStatusCommand.self])
}

private struct ProfileShowCommand: PolicyCommand {
  static let operation = Command.profile
  static let abstract = "Print the configuration profile without installing it"
  @OptionGroup var options: PolicyOptions
}

private struct ProfileOpenCommand: PolicyCommand {
  static let operation = Command.openProfile
  static let abstract = "Generate a profile and open System Settings for installation"
  @OptionGroup var options: PolicyOptions
}

private struct ProfileStatusCommand: PolicyCommand {
  static let operation = Command.profileStatus
  static let abstract = "Show whether the Pared profile is installed, without sudo"
  @OptionGroup var options: PolicyOptions
}

private struct ModelsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "models", abstract: "Inspect, download, or remove model sets",
    discussion: """
      Cleanup removes sets only when all known consumers are disabled.
      Cleanup checks remaining model folders; locked or unreadable files prevent
      a successful result. Close affected apps or restart before checking again.
      Download requires an enabled feature with a catalog download mapping.
      An accepted request does not mean the download has finished.
      Status reports a snapshot, not live progress; query or inventory errors exit 1.
      """,
    subcommands: [
      ModelsStatusCommand.self, ModelsDownloadCommand.self, ModelsCleanupCommand.self,
      ModelsCheckCommand.self,
    ])
}

private struct ModelsStatusCommand: PolicyCommand {
  static let operation = Command.models
  static let abstract = "Show model snapshots and local asset directories as JSON"
  @OptionGroup var options: PolicyOptions
  @Argument(help: "Feature names or 'all'; omit to inspect every feature", completion: .features)
  var features: [String] = []
}

private struct ModelsDownloadCommand: PolicyCommand {
  static let operation = Command.download
  static let abstract = "Ask Apple to download models for enabled features"
  @OptionGroup var options: PolicyOptions
  @Argument(help: "Enabled feature names or 'all'", completion: .features) var features: [String]
  @Flag(help: "Preview download requests without sending them") var dryRun = false
}

private struct ModelsCleanupCommand: PolicyCommand {
  static let operation = Command.cleanup
  static let abstract = "Remove only models whose known consumers are disabled"
  @OptionGroup var options: PolicyOptions
  @Argument(help: "Feature names or 'all'; omit to consider every feature", completion: .features)
  var features: [String] = []
  @Flag(help: "Print eligible model sets without removing them") var dryRun = false
}

private struct ModelsCheckCommand: PolicyCommand {
  static let operation = Command.check
  static let abstract = "Check service access by requesting a nonexistent asset set"
  @OptionGroup var options: PolicyOptions
}

private struct WizardCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wizard", abstract: "Open the guided installation and feature setup menu",
    discussion: """
      Choose guided setup to choose features, apply the profile in System Settings,
      review optional model cleanup, and install the command. Skip any step or return
      to the menu. Completed actions are kept. In the wizard, --policy can also
      name a new policy file.

      Nothing changes until you confirm an action. Use arrow keys to move and Enter
      to select; Space toggles features and / searches. Review the complete feature
      policy, make more changes, or discard the draft before saving. Installing
      the command does not change feature settings or remove models. Profile
      installation still requires your approval in System Settings.
      """)

  @OptionGroup var options: PolicyOptions
  @Option(
    help: ArgumentHelp("Suggested installation directory (default: ~/.local)", valueName: "dir"),
    completion: .directory, transform: wizardPrefix)
  var prefix: URL?

  mutating func run() async throws {
    let status = try await runWizard(prefix: prefix, policyURL: options.url)
    if status != .success { throw ExitCode(status.rawValue) }
  }
}

private struct GUICommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "gui", abstract: "Open the macOS app")
  @OptionGroup var options: PolicyOptions

  mutating func run() {
    let policyURL = options.url
    MainActor.assumeIsolated {
      ParedApp.initialPolicyURL = policyURL
      ParedApp.main()
    }
  }
}
