import Foundation

// Command paths are also used in diagnostics and group help
enum Command: String, CaseIterable {
  case features, status, enable, disable, reset, apply
  case wizard
  case profile = "profile show"
  case openProfile = "profile open"
  case profileStatus = "profile status"
  case declarations
  case cleanup = "models cleanup"
  case download = "models download"
  case models = "models status"
  case check = "models check"

  static func subcommands(for group: String) -> [Command] {
    allCases.filter { $0.rawValue.hasPrefix(group + " ") }
  }

  static func parse(_ arguments: inout ArraySlice<String>) throws(CLIError) -> Command {
    guard let first = arguments.popFirst() else { throw CLIError("Expected a command") }
    let children = subcommands(for: first)
    let path: String
    if children.isEmpty {
      path = first
    } else {
      guard let child = arguments.popFirst() else {
        throw CLIError("\(first) requires a subcommand")
      }
      path = first + " " + child
    }
    guard let command = Command(rawValue: path) else {
      throw CLIError("Unknown command: \(path). Run pared --help for available commands.")
    }
    return command
  }

  struct Definition {
    enum Features: String {
      case none = ""
      case optional = " [features...]"
      case required = " <features...|all>"
      case download = " <features...>"
    }

    let summary: String
    var features: Features = .none
    var acceptsDryRun = false
    var desiredState: FeatureState? = nil
  }

  var definition: Definition {
    switch self {
    case .wizard:
      return Definition(summary: "Open the guided installation and Apple Intelligence setup menu")
    case .features:
      return Definition(
        summary: "List feature names and their preference, profile, and model controls")
    case .status:
      return Definition(
        summary: "Show desired policy and observed preferences as JSON", features: .optional)
    case .enable:
      return Definition(
        summary: "Enable features; save policy, profile, and MDM declarations", features: .required,
        acceptsDryRun: true, desiredState: .enabled)
    case .disable:
      return Definition(
        summary: "Disable features; save policy, profile, and MDM declarations",
        features: .required,
        acceptsDryRun: true, desiredState: .disabled)
    case .reset:
      return Definition(
        summary: "Remove local preferences; mark features unmanaged", features: .required,
        acceptsDryRun: true, desiredState: .unmanaged)
    case .apply:
      return Definition(
        summary: "Apply policy preferences; save profile and MDM declarations", acceptsDryRun: true)
    case .profile:
      return Definition(summary: "Print the configuration profile without installing it")
    case .openProfile:
      return Definition(summary: "Generate a profile and open System Settings for installation")
    case .profileStatus:
      return Definition(summary: "Show whether the Pared profile is installed, without sudo")
    case .declarations:
      return Definition(summary: "Print macOS 27 MDM configuration declarations")
    case .cleanup:
      return Definition(
        summary: "Remove only models whose known consumers are disabled", features: .optional,
        acceptsDryRun: true)
    case .download:
      return Definition(
        summary: "Ask Apple to download models for enabled features", features: .download,
        acceptsDryRun: true)
    case .models:
      return Definition(
        summary: "Show model snapshots and local asset directories as JSON", features: .optional)
    case .check:
      return Definition(summary: "Check service access by requesting a nonexistent asset set")
    }
  }

  var acceptsFeatures: Bool { definition.features != .none }
  var acceptsDryRun: Bool { definition.acceptsDryRun }
  var desiredState: FeatureState? { definition.desiredState }

  static var help: String {
    let synopsisWidth =
      allCases.map { ($0.rawValue + $0.definition.features.rawValue).count }.max() ?? 0
    return allCases.map { command in
      let synopsis = command.rawValue + command.definition.features.rawValue
      return "  " + synopsis + String(repeating: " ", count: synopsisWidth - synopsis.count + 2)
        + command.definition.summary
    }.joined(separator: "\n")
  }
}

enum CLIOption: String {
  case policy = "--policy"
  case dryRun = "--dry-run"
  case help = "--help"
  case shortHelp = "-h"

  static func isHelp(_ arguments: ArraySlice<String>) -> Bool {
    arguments.count == 1
      && arguments.first.map { $0 == help.rawValue || $0 == shortHelp.rawValue } == true
  }
}
