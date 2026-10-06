import SwiftUI

struct ModelsPane: View {
  @Bindable var store: GUIStore
  @State private var sortOrder = [KeyPathComparator(\ModelRow.title)]
  @State private var showsDownloads = false

  private var modelRows: [ModelRow] {
    (store.catalog?.assetTypes.keys.sorted() ?? []).map { asset in
      let status = store.modelStatuses[asset]
      return ModelRow(
        id: asset, title: store.modelTitle(asset),
        snapshot: status?.summary ?? "Not checked yet",
        reportedBytes: status?.localSnapshot?.downloadedFilesystemBytes,
        policy: !store.policyExists
          ? "Not saved" : store.cleanupTargets.contains(asset) ? "Eligible" : "Retained")
    }.sorted(using: sortOrder)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeading(
          title: "Downloaded Models",
          description:
            "Review what can be removed, or request models for a feature you’ve enabled.",
          symbol: "internaldrive")
        GroupBox("Remove Models") {
          VStack(alignment: .leading, spacing: 12) {
            Label(
              !store.policyExists
                ? "Save your choices to review removal"
                : store.cleanupTargets.isEmpty
                  ? "All model sets are retained by your saved choices"
                  : "\(store.cleanupTargets.count) model sets eligible for removal",
              systemImage: store.cleanupTargets.isEmpty ? "shield" : "internaldrive"
            )
            .font(.headline)
            Text(
              "Pared removes a model set only when every consumer in its catalog is disabled. A retained set can still serve another feature."
            )
            .foregroundStyle(.secondary)
            if let requirement = store.savedPolicyRequirement {
              Text("Eligibility is based on your saved policy.")
                .font(.caption).foregroundStyle(.secondary)
              Text(requirement)
                .font(.callout).foregroundStyle(.secondary)
            }
            Button("Review Removal…", action: store.reviewCleanup)
              .disabled(!store.canUseSavedPolicy || store.cleanupTargets.isEmpty)
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = store.modelsError {
          InlineMessage(
            title: "Model status unavailable", message: error,
            symbol: "exclamationmark.triangle", isError: true)
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("Model Snapshots").font(.headline).accessibilityAddTraits(.isHeader)
          Text("A snapshot is not live download progress or a measurement of reclaimed disk space.")
            .font(.callout).foregroundStyle(.secondary)
          if let checkedAt = store.modelsCheckedAt {
            HStack(spacing: 4) {
              Text("Last checked")
              Text(checkedAt, style: .time)
            }
            .font(.caption).foregroundStyle(.secondary)
          }
          Table(modelRows, selection: $store.selectedModel, sortOrder: $sortOrder) {
            TableColumn("Model", value: \.title) { row in
              Text(row.title).help(row.title)
            }
            .width(min: 120, ideal: 180, max: 260)
            TableColumn("Snapshot", value: \.snapshot) { row in
              Text(row.snapshot).help(row.snapshot)
            }
            .width(min: 150, ideal: 200, max: 280)
            TableColumn(
              "Reported Size", value: \.self,
              comparator: KeyPathComparator(\ModelRow.reportedBytes)
            ) { row in
              Text(row.reportedSize ?? "—")
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(row.reportedSize ?? "Not available")
            }
            .width(min: 90, ideal: 110, max: 170)
            TableColumn("Removal", value: \.policy)
              .width(min: 75, ideal: 90, max: 150)
          }
          .tableStyle(.inset(alternatesRowBackgrounds: true))
          .frame(height: 210)
          .accessibilityLabel("Model snapshots")
          if let asset = store.selectedModel,
            modelRows.contains(where: { $0.id == asset })
          {
            ModelSnapshotDetail(store: store, asset: asset)
          }
        }
        DisclosureGroup("Download models again", isExpanded: $showsDownloads) {
          VStack(alignment: .leading, spacing: 14) {
            Text(
              "Enable the feature, save your choices, and install the updated profile first. Downloads continue in the background after Apple accepts the request."
            )
            .foregroundStyle(.secondary)
            ForEach(store.downloadFeatures) { feature in
              HStack(spacing: 12) {
                Image(systemName: feature.symbol).frame(width: 24).foregroundStyle(.secondary)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(feature.title)
                  Text(store.policy.state(feature.id).title)
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Download") { store.download(feature.id) }
                  .disabled(!store.canUseSavedPolicy || store.policy.state(feature.id) != .enabled)
                  .accessibilityLabel("Download models for \(feature.title)")
              }
            }
            Text("For features without a download mapping, enable them in their Apple app.")
              .font(.caption).foregroundStyle(.secondary)
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
          Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        DiagnosticsDisclosure(text: store.lastDiagnostics)
      }
      .padding(28).frame(maxWidth: 860, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }
}

private struct ModelRow: Identifiable {
  let id: String
  let title: String
  let snapshot: String
  let reportedBytes: Int64?
  let policy: String

  var reportedSize: String? {
    reportedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
  }
}

private struct ModelSnapshotDetail: View {
  let store: GUIStore
  let asset: String

  private var status: ModelStatus? {
    store.modelStatuses[asset]
  }

  private var retainedConsumers: [FeaturePresentation] {
    (store.catalog?.consumers(of: asset) ?? [])
      .filter { store.policy.state($0) != .disabled }
      .map(store.presentation)
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(store.modelTitle(asset)).font(.headline)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Label(
            !store.policyExists
              ? "Policy not saved" : retainedConsumers.isEmpty ? "Eligible" : "Retained",
            systemImage: retainedConsumers.isEmpty ? "minus.circle" : "shield"
          )
          .font(.callout).foregroundStyle(.secondary)
        }
        LabeledContent("Snapshot", value: status?.summary ?? "Not checked yet")
        if let snapshot = status?.localSnapshot {
          LabeledContent(
            "Reported filesystem size",
            value: ByteCountFormatter.string(
              fromByteCount: snapshot.downloadedFilesystemBytes, countStyle: .file))
        }
        if let directories = status?.payloadDirectories {
          LabeledContent("Local asset directories", value: String(directories.count))
        }
        if !retainedConsumers.isEmpty {
          Text(
            "Retained for: "
              + retainedConsumers.map {
                "\($0.title) (\(store.policy.state($0.id).title.lowercased()))"
              }.joined(separator: ", ")
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if status?.queryError != nil {
          Label(
            "Apple could not provide a download snapshot.", systemImage: "exclamationmark.triangle"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if status?.inventoryError != nil {
          Label(
            "Local asset folders could not be inspected.", systemImage: "folder.badge.questionmark"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup("Asset Details") {
          Text(asset).font(.caption.monospaced()).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
          if let error = status?.queryError {
            Text("Snapshot error").fontWeight(.medium).padding(.top, 8)
            Text(error).font(.caption.monospaced()).textSelection(.enabled)
          }
          if let error = status?.inventoryError {
            Text("Folder inventory error").fontWeight(.medium).padding(.top, 8)
            Text(error).font(.caption.monospaced()).textSelection(.enabled)
          }
          if let directories = status?.payloadDirectories, !directories.isEmpty {
            Text(directories.joined(separator: "\n"))
              .font(.caption.monospaced()).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .font(.caption)
      }
      .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct CleanupReview: View {
  @Bindable var store: GUIStore

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      PageHeading(
        title: "Remove These Models?",
        description: "Your saved choices turn off every feature Pared knows uses these models.",
        symbol: "internaldrive")
      VStack(alignment: .leading, spacing: 10) {
        ForEach(store.cleanupReview ?? [], id: \.self) { asset in
          Label(store.modelTitle(asset), systemImage: "cube")
        }
      }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      Text(
        "Pared asks macOS to remove these model files. You’ll need to download them again to use these features later. macOS may keep files that are still in use."
      )
      .foregroundStyle(.secondary)
      Text("Canceling removal keeps your saved feature choices.")
        .font(.caption).foregroundStyle(.secondary)
      if store.profileStatus?.installed != true || store.profileNeedsReplacement {
        Label(
          "Install the updated profile to help prevent these models from downloading again.",
          systemImage: "doc.badge.gearshape"
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      HStack {
        Button("Cancel") { store.cleanupReview = nil }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Remove Models", role: .destructive, action: store.removeReviewedModels)
          .disabled(!store.canUseSavedPolicy)
      }
    }
    .padding(28).frame(width: 510)
    .interactiveDismissDisabled(store.busy)
  }
}
