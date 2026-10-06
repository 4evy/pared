import SwiftUI

struct FeaturesPane: View {
  @Bindable var store: GUIStore

  private var filtered: [FeaturePresentation] {
    store.filteredFeatures
  }

  var body: some View {
    HSplitView {
      VStack(spacing: 0) {
        HStack {
          Picker("Show", selection: $store.featureFilter) {
            ForEach(GUIFeatureFilter.allCases) { filter in
              Text(filter.rawValue).tag(filter)
            }
          }
          .pickerStyle(.menu).labelsHidden()
          .accessibilityLabel("Filter features")
          Spacer()
          Text(String(filtered.count)).font(.caption).foregroundStyle(.secondary)
            .accessibilityLabel("\(filtered.count) features shown")
        }
        .padding(12)
        Divider()
        List(selection: $store.selectedFeature) {
          ForEach(FeaturePresentation.groups, id: \.self) { group in
            let members = filtered.filter { $0.group == group }
            if !members.isEmpty {
              Section(group) {
                ForEach(members) { feature in
                  HStack(spacing: 10) {
                    Image(systemName: feature.symbol).frame(width: 20).foregroundStyle(.secondary)
                      .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(feature.title).lineLimit(1).help(feature.title)
                      Text(store.draft.state(feature.id).title).font(.caption).foregroundStyle(
                        .secondary)
                    }
                    Spacer(minLength: 0)
                    if store.draft.state(feature.id) != store.policy.state(feature.id) {
                      Image(systemName: "pencil").font(.caption)
                        .accessibilityLabel("Unsaved change")
                    }
                  }
                  .padding(.vertical, 4)
                  .tag(feature.id)
                }
              }
            }
          }
        }
        .overlay {
          if filtered.isEmpty {
            ContentUnavailableView {
              Label(
                store.featureFilter == .changes && store.search.isEmpty
                  ? "No Unsaved Changes" : "No Matching Features",
                systemImage: store.featureFilter == .changes
                  ? "checkmark.circle" : "magnifyingglass")
            } description: {
              Text("Change the filter or search to see more features.")
            } actions: {
              Button("Show All Features") {
                store.search = ""
                store.featureFilter = .all
              }
            }
          }
        }
        Divider()
        HStack {
          Menu("Set All") {
            Button("Enable All") { store.setAll(.enabled) }
            Button("Disable All") { store.setAll(.disabled) }
            Button("Leave All Unmanaged") { store.setAll(.unmanaged) }
          }
          .disabled(store.busy || store.readOnly || !store.loaded)
          Spacer()
          Button("Discard Changes", action: store.discardChanges)
            .disabled(store.working || !store.hasChanges)
        }
        .padding(12)
      }
      .frame(minWidth: 235, idealWidth: 275, maxWidth: 340)

      if let name = store.selectedFeature, let feature = store.catalog?.features[name] {
        FeatureDetail(store: store, name: name, feature: feature)
          .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView("Select a Feature", systemImage: "switch.2")
          .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .searchable(text: $store.search, prompt: "Search features")
    .onChange(of: filtered.map(\.id)) { store.selectVisibleFeature() }
    .onAppear { store.selectVisibleFeature() }
  }
}

private struct FeatureDetail: View {
  @Bindable var store: GUIStore
  let name: String
  let feature: Feature

  private var presentation: FeaturePresentation { FeaturePresentation(name) }
  private var status: GUIFeatureStatus? { store.featureStatuses[name] }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeading(
          title: presentation.title, description: feature.description,
          symbol: presentation.symbol)
        GroupBox("Your Policy") {
          VStack(alignment: .leading, spacing: 12) {
            Picker(
              "Feature state",
              selection: Binding(
                get: { store.draft.state(name) },
                set: { store.draft.features[name] = $0 }
              )
            ) {
              Text("Enabled").tag(FeatureState.enabled)
              Text("Disabled").tag(FeatureState.disabled)
              Text("Unmanaged").tag(FeatureState.unmanaged)
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Policy for \(presentation.title)")
            .disabled(store.busy || store.readOnly || !store.loaded)
            Text(stateDescription).font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if store.draft.state(name) != store.policy.state(name) {
              Label(
                "Unsaved · currently \(store.policy.state(name).title.lowercased()) in your policy",
                systemImage: "pencil"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        if feature.preferences.isEmpty && feature.restrictions.isEmpty
          && feature.declarations.isEmpty
        {
          InlineMessage(
            title: "Model availability only",
            message:
              "This choice controls whether Pared retains these models. It does not change the feature’s settings in its Apple app.",
            symbol: "cube")
        } else if !feature.restrictions.isEmpty || !feature.declarations.isEmpty
          || !feature.assetSets.isEmpty
        {
          InlineMessage(
            title: "Profile required",
            message:
              "Save your choices, then install the updated profile. Your saved policy alone does not prove macOS is enforcing it.",
            symbol: "doc.badge.gearshape")
        }
        if !feature.declarations.isEmpty && feature.restrictions.isEmpty
          && feature.preferences.isEmpty
        {
          Text(
            "The feature restriction is available through MDM declarations. Installing a profile here only manages its model downloads."
          )
          .font(.callout).foregroundStyle(.secondary)
        }
        if !feature.preferences.isEmpty {
          GroupBox("Observed Preferences") {
            VStack(alignment: .leading, spacing: 12) {
              if let error = store.statusError {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
              } else if let status {
                ForEach(Array(status.preferences.enumerated()), id: \.offset) { _, preference in
                  VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                      Text(FeaturePresentation.preferenceTitle(preference.key)).fontWeight(.medium)
                      Spacer()
                      let inverted =
                        feature.preferences.first {
                          $0.domain == preference.domain && $0.key == preference.key
                        }?.inverted ?? false
                      Text(
                        preference.value.map { $0 != inverted ? "Enabled" : "Disabled" }
                          ?? "Not set")
                    }
                    if preference.forced {
                      Label("Enforced by a management profile", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                  }
                  .textSelection(.enabled)
                }
                Text(
                  "These values reflect mapped preferences, not complete feature availability. Relaunch affected apps after saving."
                )
                .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Preference Details") {
                  ForEach(Array(status.preferences.enumerated()), id: \.offset) { _, preference in
                    VStack(alignment: .leading, spacing: 4) {
                      Text("\(preference.domain) · \(preference.key)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                      Text(
                        "Raw value: "
                          + (preference.value.map { $0 ? "true" : "false" } ?? "not set")
                      )
                      .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                  }
                }
              } else {
                Text("Preferences have not been checked yet.").foregroundStyle(.secondary)
              }
            }
            .font(.callout).padding(8).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if !feature.assetSets.isEmpty {
          GroupBox("Models Used") {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(feature.assetSets, id: \.self) { asset in
                VStack(alignment: .leading, spacing: 4) {
                  Text(FeaturePresentation.modelTitle(asset)).fontWeight(.medium)
                  Text(
                    store.modelStatuses.first { $0.assetSet == asset }?.summary ?? "Not checked yet"
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
              Text("Shared models remain if any known consumer is enabled or unmanaged.")
                .font(.caption).foregroundStyle(.secondary)
              Button("Show Models") { store.section = .models }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        DiagnosticsDisclosure(text: store.lastDiagnostics)
      }
      .padding(24).frame(maxWidth: 700, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var stateDescription: String {
    switch store.draft.state(name) {
    case .enabled:
      "Permit this feature and retain its models. Enabling it does not download models."
    case .disabled:
      "Disable the mapped controls. Models become eligible for removal only when every known consumer is disabled."
    case .unmanaged:
      "Remove Pared’s local preference overrides when saved. Replace the profile to remove its controls. Previous preference values are not restored."
    }
  }
}
