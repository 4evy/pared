import SwiftUI

private struct PreferenceRow: Identifiable {
  let id: Preference.ID
  let title: String
  let value: String
  let rawValue: String
  let forced: Bool

  init(status: PreferenceStatus, definition: Preference?) {
    id = status.id
    title = definition?.title ?? status.key
    value =
      status.value.map { $0 != (definition?.inverted ?? false) ? "Enabled" : "Disabled" }
      ?? "Not set"
    rawValue = status.value.map { $0 ? "true" : "false" } ?? "not set"
    forced = status.forced
  }
}

struct FeaturePreferences: View {
  let feature: Feature
  let status: FeatureStatus?
  let error: String?

  private var rows: [PreferenceRow] {
    (status?.preferences ?? []).map { status in
      PreferenceRow(status: status, definition: feature.preferences.first { $0.id == status.id })
    }
  }

  var body: some View {
    SettingsGroup(title: "Current Settings") {
      if let error {
        Text(error).foregroundStyle(.secondary).textSelection(.enabled)
      } else if status != nil {
        ForEach(rows) { row in
          VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
              Text(row.value)
            } label: {
              Text(row.title).fontWeight(.medium)
            }
            if row.forced {
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
          ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(row.id.domain) · \(row.id.key)")
                .font(.caption.monospaced()).textSelection(.enabled)
              Text("Raw value: \(row.rawValue)")
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
          }
        }
      } else {
        Text("Preferences have not been checked yet.").foregroundStyle(.secondary)
      }
    }
    .font(.callout)
  }
}
