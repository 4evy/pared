import SwiftUI

// Shared by menus, toolbars, and panes so availability cannot drift
enum GUIAction: Hashable, Identifiable {
  case openSettings
  case useDefaultSettings
  case save
  case discard
  case reviewChanges
  case exportProfile
  case refresh
  case installProfile
  case reviewRemoval
  case quick(GUIQuickAction)
  case download(String)
  case setFeature(String, FeatureState)
  case setAll(FeatureState)
  case show(GUISection)
  case chooseFeatures
  case findFeatures

  var id: Self { self }

  static let settings: [Self] = [.openSettings, .useDefaultSettings]
  static let editing: [Self] = [.save, .discard, .reviewChanges]
  static let maintenance: [Self] = [.refresh, .installProfile, .reviewRemoval]
  static let quickActions: [Self] = [.quick(.turnOffAll), .quick(.turnOffAndRemoveAll)]

  @MainActor func title(in store: GUIStore) -> String {
    switch self {
    case .openSettings: "Open Settings File…"
    case .useDefaultSettings: "Use Default Settings"
    case .save: store.policyExists ? "Save Changes" : "Save Choices"
    case .discard: "Discard Changes"
    case .reviewChanges: "Review Changes"
    case .exportProfile: "Export Profile…"
    case .refresh: "Refresh Status"
    case .installProfile:
      store.profileNeedsReplacement ? "Install Updated Profile…" : "Install Profile…"
    case .reviewRemoval: "Review Model Removal…"
    case .quick(let action): action.title
    case .download: "Download"
    case .setFeature(_, let state): state.title
    case .setAll(let state): state.bulkActionTitle
    case .show(let section): "Show \(section.rawValue)"
    case .chooseFeatures: "Choose Features"
    case .findFeatures: "Find Features"
    }
  }

  var shortcut: KeyboardShortcut? {
    switch self {
    case .openSettings: KeyboardShortcut("o")
    case .save: KeyboardShortcut("s")
    case .refresh: KeyboardShortcut("r")
    case .installProfile: KeyboardShortcut("i", modifiers: [.command, .shift])
    case .findFeatures: KeyboardShortcut("f")
    case .show(let section):
      KeyboardShortcut(KeyEquivalent(Character(String(section.ordinal))))
    default: nil
    }
  }

  @MainActor func isEnabled(in store: GUIStore) -> Bool {
    switch self {
    case .openSettings: !store.working
    case .useDefaultSettings: !store.working && store.policyURL != Policy.defaultURL
    case .save: store.canSave
    case .discard: !store.working && store.hasChanges
    case .reviewChanges: store.hasChanges
    case .exportProfile, .installProfile: store.canUseSavedPolicy
    case .refresh: !store.working && store.catalog != nil
    case .reviewRemoval: store.canUseSavedPolicy && !store.cleanupTargets.isEmpty
    case .quick(let action):
      store.canEditChoices
        && (action.featureName.map { store.catalog?.features[$0]?.recovery != nil } ?? true)
    case .download(let name):
      store.canUseSavedPolicy && store.policy.state(name) == .enabled
        && store.catalog?.features[name]?.recovery != nil
    case .setFeature(let name, _): store.canEditChoices && store.catalog?.features[name] != nil
    case .setAll: store.canEditChoices
    case .chooseFeatures: store.loaded
    case .show, .findFeatures: true
    }
  }
}

extension GUIStore {
  func send(_ action: GUIAction) {
    guard action.isEnabled(in: self) else { return }
    switch action {
    case .openSettings: choosePolicy()
    case .useDefaultSettings: useDefaultPolicy()
    case .save: save()
    case .discard: discardChanges()
    case .reviewChanges: showChanges()
    case .exportProfile: exportProfile()
    case .refresh: refresh()
    case .installProfile: openProfile()
    case .reviewRemoval: reviewCleanup()
    case .quick(let action): reviewQuickAction(action)
    case .download(let name): download(name)
    case .setFeature(let name, let state): setFeature(name, to: state)
    case .setAll(let state): setAll(state)
    case .show(let destination): section = destination
    case .chooseFeatures:
      search = ""
      featureFilter = .all
      section = .features
    case .findFeatures: findFeatures()
    }
  }
}

struct GUIActionButton: View {
  let store: GUIStore
  let action: GUIAction
  var title: String? = nil
  var symbol: String? = nil
  var role: ButtonRole? = nil
  var fillsWidth = false

  var body: some View {
    Button(role: role) {
      store.send(action)
    } label: {
      Group {
        if let symbol {
          Label(title ?? action.title(in: store), systemImage: symbol)
        } else {
          Text(title ?? action.title(in: store))
        }
      }
      .frame(maxWidth: fillsWidth ? .infinity : nil)
      .contentShape(Rectangle())
    }
    .disabled(!action.isEnabled(in: store))
  }
}

struct FeatureStateActions: View {
  let store: GUIStore
  var feature: String? = nil

  var body: some View {
    ForEach(FeatureState.allCases, id: \.self) { state in
      GUIActionButton(
        store: store, action: feature.map { .setFeature($0, state) } ?? .setAll(state))
    }
  }
}

struct GUICommands: Commands {
  let store: GUIStore
  let updates: GUIUpdater

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      CheckForUpdatesButton(updates: updates, store: store)
      GUIActionButton(store: store, action: .show(.updates), title: "Changelog")
    }
    CommandGroup(replacing: .newItem) { buttons(GUIAction.settings) }
    CommandGroup(replacing: .saveItem) {
      buttons(GUIAction.editing)
      Divider()
      GUIActionButton(store: store, action: .exportProfile)
    }
    CommandMenu("Actions") {
      buttons(GUIAction.maintenance)
      Divider()
      Menu("Set Selected Feature") {
        if let name = store.selectedFeature { FeatureStateActions(store: store, feature: name) }
      }
      .disabled(store.section != .features || store.selectedFeature == nil || !store.canEditChoices)
      Menu("Set All Features") { FeatureStateActions(store: store) }
        .disabled(!store.canEditChoices)
      buttons(GUIAction.quickActions)
      Menu("Download Models") {
        ForEach(store.downloadFeatures) { feature in
          GUIActionButton(store: store, action: .download(feature.id), title: feature.title)
        }
      }
    }
    CommandGroup(after: .textEditing) { buttons([.findFeatures]) }
    CommandGroup(after: .sidebar) { buttons(GUISection.allCases.map(GUIAction.show)) }
    CommandGroup(replacing: .help) {
      Link("Pared Help", destination: URL(string: "https://github.com/4evy/pared#use")!)
      GUIActionButton(store: store, action: .show(.updates), title: "Changelog")
    }
  }

  private func buttons(_ actions: [GUIAction]) -> some View {
    ForEach(actions) { action in
      GUIActionButton(store: store, action: action).keyboardShortcut(action.shortcut)
    }
  }
}
