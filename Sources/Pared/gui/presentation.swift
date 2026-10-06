import Foundation

extension FeatureState {
  private struct Presentation {
    let title: String
    let wizardTitle: String
    let symbol: String
    let bulkActionTitle: String
    let detail: String
  }

  private var presentation: Presentation {
    switch self {
    case .enabled:
      Presentation(
        title: "On", wizardTitle: "On", symbol: "checkmark.circle",
        bulkActionTitle: "Turn All On",
        detail: "Permit this feature and retain its models. Enabling it does not download models.")
    case .disabled:
      Presentation(
        title: "Off", wizardTitle: "Off", symbol: "minus.circle",
        bulkActionTitle: "Turn All Off",
        detail:
          "Turn off the controls Pared supports. Shared models can be removed once every feature Pared knows uses them is off."
      )
    case .unmanaged:
      Presentation(
        title: "App Default", wizardTitle: "Leave alone", symbol: "circle.dashed",
        bulkActionTitle: "Use App Defaults",
        detail:
          "Stop overriding this feature’s local settings. Install the updated profile to remove Pared’s managed controls. This does not restore older setting values."
      )
    }
  }

  var title: String { presentation.title }
  var wizardTitle: String { presentation.wizardTitle }
  var symbol: String { presentation.symbol }
  var bulkActionTitle: String { presentation.bulkActionTitle }
  var detail: String { presentation.detail }
}

enum GUISection: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case features = "Features"
  case models = "Models"
  case profile = "Setup"
  case updates = "Updates"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .overview: "house"
    case .features: "switch.2"
    case .models: "internaldrive"
    case .profile: "doc.badge.gearshape"
    case .updates: "arrow.down.circle"
    }
  }
}

enum GUIQuickAction: Identifiable, Equatable {
  case turnOffAll
  case turnOffAndRemoveAll
  case enableFeature(String)

  var id: String {
    switch self {
    case .turnOffAll: "off"
    case .turnOffAndRemoveAll: "off-and-remove"
    case .enableFeature(let name): "enable-\(name)"
    }
  }
}

enum GUIFeatureFilter: Hashable, CaseIterable, Identifiable {
  case all
  case state(FeatureState)
  case changes

  static var allCases: [Self] { [.all] + FeatureState.allCases.map(Self.state) + [.changes] }

  var id: Self { self }

  var title: String {
    switch self {
    case .all: "All Features"
    case .state(let state): state.title
    case .changes: "Unsaved Changes"
    }
  }

  func includes(_ name: String, draft: Policy, saved: Policy) -> Bool {
    switch self {
    case .all: true
    case .state(let state): draft.state(name) == state
    case .changes: draft.state(name) != saved.state(name)
    }
  }
}
