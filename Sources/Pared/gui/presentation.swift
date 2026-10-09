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

  var ordinal: Int { Self.allCases.firstIndex(of: self)! + 1 }

  var sidebarGroup: GUISidebarGroup {
    switch self {
    case .features, .models, .profile: .customize
    case .overview: .primary
    case .updates: .application
    }
  }

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

enum GUISidebarGroup: CaseIterable, Identifiable {
  case primary
  case customize
  case application

  var id: Self { self }
  var title: String? { self == .customize ? "Customize" : nil }
  var sections: [GUISection] { GUISection.allCases.filter { $0.sidebarGroup == self } }
}

enum GUIQuickAction: Identifiable, Hashable {
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

  var featureName: String? {
    if case .enableFeature(let name) = self { name } else { nil }
  }

  var title: String {
    switch self {
    case .turnOffAll: "Turn Off All…"
    case .turnOffAndRemoveAll: "Turn Off & Review Removal…"
    case .enableFeature: "Get Models…"
    }
  }

  func review(featureTitle: String?) -> QuickActionPresentation {
    switch self {
    case .turnOffAll:
      QuickActionPresentation(
        title: "Turn Off All Features?",
        description: "Save every feature Pared manages as off. Downloaded models stay on your Mac.",
        confirmTitle: "Turn Off All",
        pendingChanges: "This replaces your unsaved feature choices with all features off.")
    case .turnOffAndRemoveAll:
      QuickActionPresentation(
        title: "Turn Off Features & Remove Models?",
        description:
          "Save every feature Pared manages as off, then review all supported model groups for removal. No model files are removed at this step.",
        confirmTitle: "Turn Off & Review Removal",
        pendingChanges: "This replaces your unsaved feature choices with all features off.")
    case .enableFeature(let name):
      QuickActionPresentation(
        title: "Get \(featureTitle ?? name) Models?",
        description:
          "Turn this feature on in your choices. Next, install the updated profile and request its models. Other features keep their current choices.",
        confirmTitle: "Enable & Continue",
        pendingChanges: "Your other unsaved feature choices will also be saved.")
    }
  }
}

struct QuickActionPresentation {
  let title: String
  let description: String
  let confirmTitle: String
  let pendingChanges: String
}

struct FeatureChoiceCount: Identifiable {
  let state: FeatureState
  let count: Int
  var id: FeatureState { state }
  var summary: String { "\(count) \(state.title.lowercased())" }
}

struct FeaturePresentationGroup: Identifiable {
  let group: FeatureGroup
  let features: [FeaturePresentation]
  var id: FeatureGroup { group }
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
