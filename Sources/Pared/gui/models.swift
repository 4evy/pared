import SwiftUI

struct ModelsPane: View {
  @Bindable var store: GUIStore

  private var modelRows: [ModelRow] {
    (store.catalog?.assetTypes.keys.sorted() ?? []).map { asset in
      let status = store.modelStatuses.first { $0.assetSet == asset }
      return ModelRow(
        id: asset, title: FeaturePresentation.modelTitle(asset),
        snapshot: status?.summary ?? "Not checked yet",
        reportedSize: status?.localSnapshot.map {
          ByteCountFormatter.string(
            fromByteCount: $0.downloadedFilesystemBytes, countStyle: .file)
        },
        policy: !store.policyExists
          ? "Not saved" : store.cleanupTargets.contains(asset) ? "Eligible" : "Retained")
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeading(
          title: "Manage Downloaded Models",
          description:
            "Review what can be removed, or request models for a feature you’ve enabled.",
          symbol: "internaldrive")
        GroupBox("Remove Models") {
          VStack(alignment: .leading, spacing: 12) {
            Label(
              !store.policyExists
                ? "Save a policy to review removal"
                : store.cleanupTargets.isEmpty
                  ? "All model sets are retained by your policy"
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
          Text("Model Snapshots").font(.headline)
          Text("A snapshot is not live download progress or a measurement of reclaimed disk space.")
            .font(.callout).foregroundStyle(.secondary)
          if let checkedAt = store.modelsCheckedAt {
            HStack(spacing: 4) {
              Text("Last checked")
              Text(checkedAt, style: .time)
            }
            .font(.caption).foregroundStyle(.secondary)
          }
          Table(modelRows, selection: $store.selectedModel) {
            TableColumn("Model", value: \.title)
              .width(min: 120, ideal: 180, max: 260)
            TableColumn("Snapshot", value: \.snapshot)
              .width(min: 120, ideal: 180, max: 280)
            TableColumn("Reported Size") { row in
              Text(row.reportedSize ?? "—")
                .accessibilityLabel(row.reportedSize ?? "Not available")
            }
            .width(min: 90, ideal: 110, max: 170)
            TableColumn("Policy", value: \.policy)
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
        GroupBox("Download Again") {
          VStack(alignment: .leading, spacing: 14) {
            Text(
              "Enable the feature, save, and install the replacement profile first. Requests continue downloading in the background after Apple accepts them."
            )
            .foregroundStyle(.secondary)
            ForEach(store.features.filter { store.catalog?.features[$0.id]?.recovery != nil }) {
              feature in
              HStack(spacing: 12) {
                Image(systemName: feature.symbol).frame(width: 24).foregroundStyle(.secondary)
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
        DiagnosticsDisclosure(text: store.lastDiagnostics)
      }
      .padding(28).frame(maxWidth: 880, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }
}

private struct ModelRow: Identifiable {
  let id: String
  let title: String
  let snapshot: String
  let reportedSize: String?
  let policy: String
}

private struct ModelSnapshotDetail: View {
  let store: GUIStore
  let asset: String

  private var status: GUIModelStatus? {
    store.modelStatuses.first { $0.assetSet == asset }
  }

  private var retainedConsumers: [FeaturePresentation] {
    store.features.filter {
      store.catalog?.features[$0.id]?.assetSets.contains(asset) == true
        && store.policy.state($0.id) != .disabled
    }
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(FeaturePresentation.modelTitle(asset)).font(.headline)
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
        title: "Remove These Model Sets?",
        description: "Every known consumer of these sets is disabled in your saved policy.",
        symbol: "internaldrive")
      VStack(alignment: .leading, spacing: 10) {
        ForEach(store.cleanupReview ?? [], id: \.self) { asset in
          Label(FeaturePresentation.modelTitle(asset), systemImage: "cube")
        }
      }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      Text(
        "This requests removal through Apple’s asset service. You’ll need to download the models again to use them later. System Integrity Protection stays enabled."
      )
      .foregroundStyle(.secondary)
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
