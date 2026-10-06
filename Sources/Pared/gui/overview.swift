import SwiftUI

struct OverviewPane: View {
  @Bindable var store: GUIStore
  @State private var showsDownloads = false

  private var preparingDownload: String? {
    guard store.loaded, store.policyExists, let name = store.downloadPreparation,
      store.policy.state(name) == .enabled
    else { return nil }
    return name
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          PageHeading(
            title: "Apple Intelligence",
            description: "Keep what you use. Turn off the rest and remove its downloaded models.",
            symbol: "switch.2")
          if store.hasChanges { unsavedChanges }
          choiceSummary
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
            featureActions
            modelActions
          }
          if let name = preparingDownload {
            downloadSetup(name)
              .id("download-setup")
          } else if store.policyExists
            && (store.profileNeedsReplacement || store.profileStatus?.installed != true)
          {
            profileSetup
          }
          DisclosureGroup(isExpanded: $showsDownloads) {
            downloadChoices.padding(.top, 16)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text("Use a feature again").font(.headline)
              Text("Enable a feature and download its models.")
                .font(.callout).foregroundStyle(.secondary)
            }
          }
          .padding(20)
          .background(
            Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(28).frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
      }
      .onChange(of: preparingDownload) { _, name in
        if name != nil {
          withAnimation { proxy.scrollTo("download-setup", anchor: .top) }
        }
      }
    }
  }

  private var choiceSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        store.policyExists
          ? (store.hasChanges ? "Your draft choices" : "Your saved choices")
          : "Start with your choices"
      )
      .font(.headline).accessibilityAddTraits(.isHeader)
      if store.loaded && store.policyError == nil {
        HStack(spacing: 0) {
          ForEach(FeatureState.allCases, id: \.self) { state in
            if state != FeatureState.allCases.first { Divider().frame(height: 36) }
            VStack(alignment: .leading, spacing: 4) {
              Text(String(store.features.count { store.draft.state($0.id) == state }))
                .font(.title2.weight(.semibold)).monospacedDigit()
              Label(state.title, systemImage: state.symbol)
                .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
          }
        }
        Text(
          store.policyExists
            ? "Saved choices and installed controls are separate. Check Setup after making changes."
            : "All choices start off. Nothing changes on your Mac until you save."
        )
        .font(.caption).foregroundStyle(.secondary)
      } else {
        Text(
          store.policyError == nil
            ? "Loading your choices…" : "Open a valid settings file to see your choices."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
  }

  private var featureActions: some View {
    OverviewActionCard(
      title: "Choose what stays on",
      description:
        "Keep the features you use and turn off the rest.",
      symbol: "switch.2"
    ) {
      Button("Choose Features") {
        store.search = ""
        store.featureFilter = .all
        store.section = .features
      }
      .buttonStyle(.borderedProminent)
      .disabled(!store.loaded)
      Button("Turn Off All…") { store.reviewQuickAction(.turnOffAll) }
        .disabled(!store.canEditChoices || allOff)
    }
  }

  private var modelActions: some View {
    OverviewActionCard(
      title: "Remove unwanted models",
      description:
        "Shared models stay while another feature needs them.",
      symbol: "internaldrive"
    ) {
      Button("Remove Unused…", action: store.reviewCleanup)
        .disabled(!store.canUseSavedPolicy || store.cleanupTargets.isEmpty)
        .help(store.savedPolicyRequirement ?? "Review models no enabled feature needs")
      Menu("More") {
        Button("Model Details") { store.section = .models }
        Button("Turn Off & Remove All…", role: .destructive) {
          store.reviewQuickAction(.turnOffAndRemoveAll)
        }
        .disabled(!store.canEditChoices)
      }
      .fixedSize()
    }
  }

  private var allOff: Bool {
    store.policyExists && !store.hasChanges
      && store.features.allSatisfy { store.policy.state($0.id) == .disabled }
  }

  private var unsavedChanges: some View {
    HStack(spacing: 16) {
      Label("\(store.changedNames.count) unsaved changes", systemImage: "pencil.circle")
      Spacer()
      Button("Review", action: store.showChanges)
      Button("Discard", action: store.discardChanges).disabled(store.working)
      Button("Save Changes", action: store.save).disabled(!store.canSave)
    }
    .font(.callout)
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var downloadChoices: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Downloads continue in the background after Apple accepts the request.")
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        Text("Feature")
        Spacer()
        Text("Saved Choice").frame(width: 95)
        Text("Action").frame(width: 122)
      }
      .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
      ForEach(store.downloadFeatures) { feature in
        if feature.id != store.downloadFeatures.first?.id {
          Divider().padding(.leading, 44)
        }
        DownloadChoiceRow(store: store, feature: feature)
      }
      if store.working || store.hasChanges || !store.loaded,
        let requirement = store.savedPolicyRequirement
      {
        Text(requirement).font(.caption).foregroundStyle(.secondary)
      }
      Button("See Model Details") { store.section = .models }
        .buttonStyle(.link).padding(.top, 8)
    }
  }

  private var profileSetup: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Finish Setup", systemImage: "gearshape")
        .font(.headline).accessibilityAddTraits(.isHeader)
      Text("macOS needs a profile to apply some controls and block unwanted downloads.")
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        Button(
          store.profileNeedsReplacement ? "Install Updated Profile…" : "Install Profile…",
          action: store.openProfile
        )
        .disabled(!store.canUseSavedPolicy)
        Button("Setup Details") { store.section = .profile }
          .buttonStyle(.link)
      }
      Text("Complete installation in System Settings, then refresh Pared.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private func downloadSetup(_ name: String) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Get \(store.presentation(name).title) Ready")
        .font(.headline).accessibilityAddTraits(.isHeader)
      OverviewActionRow(
        title: "Install the Updated Profile",
        description: "Complete installation in System Settings so the models can download.",
        symbol: "1.circle"
      ) {
        Button {
          store.openProfile()
        } label: {
          Text("Install Profile…").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).disabled(!store.canUseSavedPolicy)
      }
      OverviewActionRow(
        title: "Download the Models",
        description:
          "Return here after installing. Pared checks for blocked downloads before sending the request.",
        symbol: "2.circle"
      ) {
        Button {
          store.download(name)
        } label: {
          Text("Download Models").frame(maxWidth: .infinity)
        }
        .disabled(!store.canUseSavedPolicy)
      }
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct OverviewActionCard<Actions: View>: View {
  let title: String
  let description: String
  let symbol: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(title, systemImage: symbol)
        .font(.headline).accessibilityAddTraits(.isHeader)
      Text(description).font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10, content: actions)
        .controlSize(.large)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct OverviewActionRow<Actions: View>: View {
  let title: String
  let description: String
  let symbol: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        .frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        Text(description).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      VStack(spacing: 10, content: actions).frame(width: 190)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct DownloadChoiceRow: View {
  @Bindable var store: GUIStore
  let feature: FeaturePresentation

  private var enabled: Bool {
    store.loaded && store.policyExists && store.policy.state(feature.id) == .enabled
  }

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: feature.symbol).font(.system(size: 18)).foregroundStyle(.secondary)
        .frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(feature.title).fontWeight(.medium)
        Text(feature.downloadPurpose).font(.caption).foregroundStyle(.secondary)
        if enabled {
          Text(snapshotSummary).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Text(choiceTitle)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .foregroundStyle(enabled ? Color.accentColor : .secondary)
        .background(
          enabled ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08),
          in: Capsule()
        )
        .frame(width: 95)
        .accessibilityLabel("Saved choice: \(choiceTitle == "—" ? "Not saved" : choiceTitle)")
        .help("Your saved choice; install the profile to apply supported controls")
      Group {
        if enabled {
          Button {
            store.download(feature.id)
          } label: {
            Text("Download").frame(maxWidth: .infinity)
          }
          .disabled(!store.canUseSavedPolicy)
          .accessibilityLabel("Download models for \(feature.title)")
        } else {
          Button {
            store.reviewQuickAction(.enableFeature(feature.id))
          } label: {
            Text("Get Models…").frame(maxWidth: .infinity)
          }
          .disabled(!store.canEditChoices)
          .accessibilityLabel("Get models for \(feature.title)")
        }
      }
      .frame(width: 122)
    }
    .padding(.vertical, 10)
  }

  private var choiceTitle: String {
    guard store.loaded, store.policyExists else { return "—" }
    return store.policy.state(feature.id).title
  }

  private var snapshotSummary: String {
    guard let asset = store.catalog?.features[feature.id]?.assetSets.first,
      let status = store.modelStatuses[asset]
    else { return "Model status not checked yet" }
    return status.summary
  }
}

struct QuickActionReview: View {
  @Bindable var store: GUIStore
  let action: GUIQuickAction

  var body: some View {
    let copy = presentation
    VStack(alignment: .leading, spacing: 20) {
      PageHeading(title: copy.title, description: copy.description, symbol: "switch.2")
      Text(
        "Saving applies the local settings Pared supports. You’ll also need to install the updated profile in System Settings. Some features require device management to fully restrict them."
      )
      .foregroundStyle(.secondary)
      if store.hasChanges {
        Text(
          action == .turnOffAll || action == .turnOffAndRemoveAll
            ? "This replaces your unsaved feature choices with all features off."
            : "Your other unsaved feature choices will also be saved."
        )
        .font(.callout)
      }
      HStack {
        Button("Cancel") { store.quickActionReview = nil }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button(copy.confirmTitle, action: store.confirmQuickAction)
          .disabled(!store.canEditChoices)
      }
    }
    .padding(28).frame(width: 510)
  }

  private var presentation: (title: String, description: String, confirmTitle: String) {
    switch action {
    case .turnOffAll:
      (
        "Turn Off All Features?",
        "Save every feature Pared manages as off. Downloaded models stay on your Mac.",
        "Turn Off All"
      )
    case .turnOffAndRemoveAll:
      (
        "Turn Off Features & Remove Models?",
        "Save every feature Pared manages as off, then review all supported model groups for removal. No model files are removed at this step.",
        "Turn Off & Review Removal"
      )
    case .enableFeature(let name):
      (
        "Get \(store.presentation(name).title) Models?",
        "Turn this feature on in your choices. Next, install the updated profile and request its models. Other features keep their current choices.",
        "Enable & Continue"
      )
    }
  }
}
