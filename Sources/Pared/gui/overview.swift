import SwiftUI

struct OverviewPane: View {
  @Bindable var store: GUIStore
  @State private var showsDownloads = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var preparingDownload: String? {
    guard store.loaded, store.policyExists, let name = store.downloadPreparation,
      store.policy.state(name) == .enabled
    else { return nil }
    return name
  }

  var body: some View {
    ScrollViewReader { proxy in
      GUIPage(spacing: 24) {
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
        GUICard {
          DisclosureGroup(isExpanded: $showsDownloads) {
            downloadChoices.padding(.top, 16)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text("Use a feature again").font(.headline)
              Text("Enable a feature and download its models.")
                .font(.callout).foregroundStyle(.secondary)
            }
          }
        }
      }
      .onChange(of: preparingDownload) { _, name in
        if name != nil {
          withAnimation(reduceMotion ? nil : .default) {
            proxy.scrollTo("download-setup", anchor: .top)
          }
        }
      }
    }
  }

  private var choiceSummary: some View {
    GUICard {
      Text(
        store.policyExists
          ? (store.hasChanges ? "Your draft choices" : "Your saved choices")
          : "Start with your choices"
      )
      .font(.headline).accessibilityAddTraits(.isHeader)
      if store.loaded && store.policyError == nil {
        HStack(spacing: 0) {
          ForEach(store.choiceCounts) { choice in
            let state = choice.state
            if state != FeatureState.allCases.first { Divider().frame(height: 36) }
            VStack(alignment: .leading, spacing: 4) {
              Text(String(choice.count))
                .font(.title2.weight(.semibold)).monospacedDigit()
              Label(state.title, systemImage: state.symbol)
                .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Feature choices")
        .accessibilityValue(
          store.choiceCounts.map(\.summary).joined(separator: ", "))
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
  }

  private var featureActions: some View {
    OverviewActionCard(
      title: "Choose what stays on",
      description:
        "Keep the features you use and turn off the rest.",
      symbol: "switch.2"
    ) {
      GUIActionButton(store: store, action: .chooseFeatures)
        .buttonStyle(.borderedProminent)
      GUIActionButton(store: store, action: .quick(.turnOffAll))
        .disabled(allOff)
    }
  }

  private var modelActions: some View {
    OverviewActionCard(
      title: "Remove unwanted models",
      description:
        "Shared models stay while another feature needs them.",
      symbol: "internaldrive"
    ) {
      GUIActionButton(store: store, action: .reviewRemoval, title: "Remove Unused…")
        .help(store.savedPolicyRequirement ?? "Review models no enabled feature needs")
      Menu("More") {
        GUIActionButton(store: store, action: .show(.models), title: "Model Details")
        GUIActionButton(
          store: store, action: .quick(.turnOffAndRemoveAll), title: "Turn Off & Remove All…",
          role: .destructive)
      }
      .fixedSize()
    }
  }

  private var allOff: Bool {
    store.policyExists && !store.hasChanges
      && store.features.allSatisfy { store.policy.state($0.id) == .disabled }
  }

  private var unsavedChanges: some View {
    GUICard(padding: 14, subtle: true) {
      Label("\(store.changedNames.count) unsaved changes", systemImage: "pencil.circle")
      HStack {
        GUIActionButton(store: store, action: .reviewChanges, title: "Review")
        GUIActionButton(store: store, action: .discard, title: "Discard")
        Spacer()
        GUIActionButton(store: store, action: .save)
      }
    }
    .font(.callout)
  }

  private var downloadChoices: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Downloads continue in the background after Apple accepts the request.")
        .font(.callout).foregroundStyle(.secondary)
      DownloadFeatures(store: store)
      if store.working || store.hasChanges || !store.loaded,
        let requirement = store.savedPolicyRequirement
      {
        Text(requirement).font(.caption).foregroundStyle(.secondary)
      }
      GUIActionButton(store: store, action: .show(.models), title: "See Model Details")
        .buttonStyle(.link).padding(.top, 8)
    }
  }

  private var profileSetup: some View {
    GUICard(padding: 16, subtle: true) {
      Label("Finish Setup", systemImage: "gearshape")
        .font(.headline).accessibilityAddTraits(.isHeader)
      Text("macOS needs a profile to apply some controls and block unwanted downloads.")
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        GUIActionButton(store: store, action: .installProfile)
        GUIActionButton(store: store, action: .show(.profile), title: "Setup Details")
          .buttonStyle(.link)
      }
      Text("Complete installation in System Settings, then refresh Pared.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func downloadSetup(_ name: String) -> some View {
    GUICard(spacing: 16, padding: 16, subtle: true) {
      Text("Get \(store.presentation(name).title) Ready")
        .font(.headline).accessibilityAddTraits(.isHeader)
      OverviewActionRow(
        title: "Install the Updated Profile",
        description: "Complete installation in System Settings so the models can download.",
        symbol: "1.circle"
      ) {
        GUIActionButton(store: store, action: .installProfile, fillsWidth: true)
          .buttonStyle(.borderedProminent)
      }
      OverviewActionRow(
        title: "Download the Models",
        description:
          "Return here after installing. Pared checks for blocked downloads before sending the request.",
        symbol: "2.circle"
      ) {
        GUIActionButton(
          store: store, action: .download(name), title: "Download Models", fillsWidth: true)
      }
    }
  }
}

private struct OverviewActionCard<Actions: View>: View {
  let title: String
  let description: String
  let symbol: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    GUICard(spacing: 16) {
      Label(title, systemImage: symbol)
        .font(.headline).accessibilityAddTraits(.isHeader)
      Text(description).font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10, content: actions)
        .controlSize(.large)
    }
  }
}

private struct OverviewActionRow<Actions: View>: View {
  let title: String
  let description: String
  let symbol: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 16) {
        heading.frame(minWidth: 220)
        Spacer(minLength: 12)
        VStack(spacing: 10, content: actions).frame(width: 190)
      }
      VStack(alignment: .leading, spacing: 12) {
        heading
        VStack(spacing: 10, content: actions).frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var heading: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        .frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        Text(description).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct QuickActionReview: View {
  @Bindable var store: GUIStore
  let action: GUIQuickAction

  var body: some View {
    let copy = action.review(featureTitle: action.featureName.map { store.presentation($0).title })
    ReviewSheet(title: copy.title, description: copy.description, symbol: "switch.2") {
      Text(
        "Saving applies the local settings Pared supports. You’ll also need to install the updated profile in System Settings. Some features require device management to fully restrict them."
      )
      .foregroundStyle(.secondary)
      if store.hasChanges {
        Text(copy.pendingChanges)
          .font(.callout)
      }
    } actions: {
      Button("Cancel") { store.review = nil }
        .keyboardShortcut(.cancelAction)
      Spacer()
      Button(copy.confirmTitle, action: store.confirmQuickAction)
        .disabled(!store.canEditChoices)
    }
  }

}
