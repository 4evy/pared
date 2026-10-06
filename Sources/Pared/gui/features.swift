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
              Text(filter.title).tag(filter)
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
          let groups = Dictionary(grouping: filtered, by: \.group)
          ForEach(FeatureGroup.allCases, id: \.self) { group in
            if let members = groups[group] {
              Section(group.rawValue) {
                ForEach(members) { feature in
                  HStack(spacing: 10) {
                    Image(systemName: feature.symbol).frame(width: 20).foregroundStyle(.secondary)
                      .accessibilityHidden(true)
                    Text(feature.title).lineLimit(2).help(feature.title)
                    Spacer(minLength: 4)
                    Text(store.draft.state(feature.id).title)
                      .font(.caption).foregroundStyle(.secondary)
                      .padding(.horizontal, 7).padding(.vertical, 3)
                      .background(.quaternary, in: Capsule())
                      .fixedSize()
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
          Menu("Set All Features") {
            ForEach(FeatureState.allCases, id: \.self) { state in
              Button(state.bulkActionTitle) { store.setAll(state) }
            }
          }
          .disabled(!store.canEditChoices)
          Spacer()
          Button("Discard Changes", action: store.discardChanges)
            .disabled(store.working || !store.hasChanges)
        }
        .padding(12)
      }
      .frame(minWidth: 270, idealWidth: 300, maxWidth: 380)

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

  private var presentation: FeaturePresentation { store.presentation(name) }
  private var status: FeatureStatus? { store.featureStatuses[name] }
  private var requiresDeviceManagement: Bool {
    !feature.declarations.isEmpty && feature.restrictions.isEmpty && feature.preferences.isEmpty
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeading(
          title: presentation.title,
          description: feature.description == presentation.title ? "" : feature.description,
          symbol: presentation.symbol)
        GroupBox("Your choice") {
          VStack(alignment: .leading, spacing: 12) {
            Picker(
              "Feature state",
              selection: Binding(
                get: { store.draft.state(name) },
                set: { store.draft.features[name] = $0 }
              )
            ) {
              ForEach(FeatureState.allCases, id: \.self) { state in
                Text(state.title).tag(state)
              }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityLabel("Your choice for \(presentation.title)")
            .disabled(!store.canEditChoices)
            Text(store.draft.state(name).detail).font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if !store.policyExists {
              Text("Draft choice · save to apply")
                .font(.caption).foregroundStyle(.secondary)
            } else if store.draft.state(name) != store.policy.state(name) {
              Label(
                "Unsaved · currently \(store.policy.state(name).title.lowercased()) in your policy",
                systemImage: "pencil"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        if feature.modelAvailabilityOnly {
          InlineMessage(
            title: "Model availability only",
            message:
              "This choice controls whether Pared retains these models. It does not change the feature’s settings in its Apple app.",
            symbol: "cube")
        } else if feature.managementRequired {
          VStack(alignment: .leading, spacing: 8) {
            Label(
              requiresDeviceManagement ? "Requires device management" : "Applies through a profile",
              systemImage: "doc.badge.gearshape"
            )
            .font(.callout.weight(.medium))
            Text(
              requiresDeviceManagement
                ? "Pared’s profile controls model downloads. Restricting the feature itself requires supervised device management."
                : "Save your choice, then install the updated profile in System Settings. Installed status does not confirm these controls are enforced."
            )
            .font(.callout).foregroundStyle(.secondary)
            Button("Review Setup") { store.section = .profile }
              .buttonStyle(.link)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let note = feature.display?.note {
          Text(note).font(.callout).foregroundStyle(.secondary)
        }
        if !feature.preferences.isEmpty {
          GroupBox("Current Settings") {
            VStack(alignment: .leading, spacing: 12) {
              if let error = store.statusError {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
              } else if let status {
                ForEach(status.preferences) { preference in
                  VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                      let definition = feature.preferences.first {
                        $0.id == preference.id
                      }
                      Text(definition?.title ?? preference.key).fontWeight(.medium)
                      Spacer()
                      let inverted =
                        definition?.inverted ?? false
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
                  ForEach(status.preferences) { preference in
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
                  Text(store.modelTitle(asset)).fontWeight(.medium)
                  Text(
                    store.modelStatuses[asset]?.summary ?? "Not checked yet"
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
              Text("Shared models remain if any known consumer is enabled or unmanaged.")
                .font(.caption).foregroundStyle(.secondary)
              Button("Show Models") {
                store.selectedModel = feature.assetSets.first
                store.section = .models
              }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        DiagnosticsDisclosure(text: store.lastDiagnostics)
      }
      .padding(24).frame(maxWidth: 700, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

}
