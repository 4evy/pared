import SwiftUI

struct DownloadFeatures: View {
  let store: GUIStore
  var allowsEnabling = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(store.downloadFeatures) { feature in
        if feature.id != store.downloadFeatures.first?.id { Divider().padding(.leading, 44) }
        DownloadFeatureRow(store: store, feature: feature, allowsEnabling: allowsEnabling)
      }
    }
  }
}

private struct DownloadFeatureRow: View {
  let store: GUIStore
  let feature: FeaturePresentation
  let allowsEnabling: Bool

  private var enabled: Bool {
    store.loaded && store.policyExists && store.policy.state(feature.id) == .enabled
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) {
        heading
        Spacer(minLength: 12)
        actions
      }
      VStack(alignment: .leading, spacing: 12) {
        heading
        actions.padding(.leading, 44)
      }
    }
    .padding(.vertical, 10)
  }

  private var heading: some View {
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
    }
  }

  private var actions: some View {
    HStack(spacing: 16) {
      ChoiceBadge(title: choiceTitle, highlighted: enabled)
        .frame(width: 95)
        .accessibilityLabel("Saved choice: \(choiceTitle == "—" ? "Not saved" : choiceTitle)")
        .help("Your saved choice; install the profile to apply supported controls")
      GUIActionButton(
        store: store,
        action: enabled || !allowsEnabling
          ? .download(feature.id) : .quick(.enableFeature(feature.id)),
        fillsWidth: true
      )
      .frame(width: 122)
      .accessibilityLabel(
        "\(enabled || !allowsEnabling ? "Download models" : "Get models") for \(feature.title)")
    }
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
