enum Command: String, CaseIterable {
  case features, status, enable, disable, reset, apply
  case profile = "profile show"
  case openProfile = "profile open"
  case profileStatus = "profile status"
  case declarations
  case cleanup = "models cleanup"
  case download = "models download"
  case models = "models status"
  case check = "models check"

  var arguments: [String] { rawValue.split(separator: " ").map(String.init) }

  var commandName: String { arguments.last! }

  var isModelCommand: Bool { arguments.first == "models" }

  var desiredState: FeatureState? {
    switch self {
    case .enable: .enabled
    case .disable: .disabled
    case .reset: .unmanaged
    default: nil
    }
  }
}
