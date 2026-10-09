import SwiftUI

struct ModelQuitOffer: Identifiable {
  let id = UUID()
  let assets: [ModelAssetSet]
  let holders: [ModelHolder]
}

struct ModelQuitReview: View {
  @Bindable var store: GUIStore
  let review: ModelQuitOffer

  var body: some View {
    ReviewSheet(
      title: "Close Model Users and Retry?",
      description: "Removal needs attention. Review processes with selected model files open.",
      symbol: "app"
    ) {
      if !review.holders.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(review.holders) { holder in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(holder.name) (PID \(holder.pid))").font(.headline)
              if let executable = holder.executable {
                Text(executable).font(.caption).textSelection(.enabled)
              }
              Text(holder.assetSets.map(store.modelTitle).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
              if !holder.canForceQuit {
                Text("Process identity unavailable; cannot force quit").font(.caption)
              }
            }
          }
        }
      }
      if review.holders.isEmpty {
        Text(
          "No holders are visible with current access. Administrator inspection can reveal system services; an empty result does not prove there are no locks."
        )
      }
      Text(
        "Save your work first. Force Quit terminates listed apps and services without save prompts. Unsaved work or running requests can be lost. Open files do not prove which process blocked removal."
      )
      Text(
        "Pared requests administrator access for holders owned by another account. It checks for remaining or restarted holders, then retries the reviewed removal once. Permission errors or remaining locks can still prevent confirmation."
      ).foregroundStyle(.secondary)
      Button("Inspect With Administrator Access", action: store.inspectModelHoldersAsAdministrator)
        .disabled(store.working)
    } actions: {
      Button("Cancel") { store.modelQuitReview = nil }
        .keyboardShortcut(.cancelAction)
        .disabled(store.working)
      Spacer()
      Button("Quit Normally") { store.quitReviewedModelApps() }
        .disabled(
          store.working || !review.holders.contains(where: \.canQuit))
      Button("Force Quit and Retry", role: .destructive) {
        store.quitReviewedModelApps(force: true)
      }
      .disabled(
        store.working || !review.holders.contains(where: \.canForceQuit))
    }
    .interactiveDismissDisabled(store.working)
  }
}
