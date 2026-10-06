import SwiftUI

struct ProfilePane: View {
  @Bindable var store: GUIStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeading(
          title: "Install Your Configuration Profile",
          description:
            "A profile enforces supported feature controls and blocks downloads for models your policy disables.",
          symbol: "doc.badge.gearshape")
        GroupBox("Installation") {
          VStack(alignment: .leading, spacing: 12) {
            if let status = store.profileStatus {
              Label(
                status.installed ? "Pared profile installed" : "Pared profile not installed",
                systemImage: status.installed ? "checkmark.seal" : "doc.badge.plus"
              )
              .font(.headline)
              if status.installed {
                Text(
                  "\(status.installedPayloadCount) payloads reported. Installed metadata does not confirm the contents match your saved policy or prove runtime enforcement."
                )
                .font(.callout).foregroundStyle(.secondary)
              }
              if !status.conflictingProfileIdentifiers.isEmpty {
                Label(
                  "Another profile uses Pared’s identity. Review it in System Settings before installing.",
                  systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
                Text(status.conflictingProfileIdentifiers.joined(separator: "\n"))
                  .font(.caption.monospaced()).textSelection(.enabled)
              }
            } else if let error = store.profileError {
              Label("Installation status unknown", systemImage: "questionmark.circle")
                .font(.headline)
              Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
              Button("Check Again", action: store.refresh).disabled(store.working)
            } else {
              Text("Installation status has not been checked yet.").foregroundStyle(.secondary)
            }
            if store.profileNeedsReplacement {
              Label(
                "Policy changed · ensure the updated profile is installed",
                systemImage: "arrow.triangle.2.circlepath"
              )
              .font(.callout)
            }
            HStack {
              Button("Install Profile…", action: store.openProfile)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canUseSavedPolicy)
              Button("Export…", action: store.exportProfile)
                .disabled(!store.canUseSavedPolicy)
            }
            if let requirement = store.savedPolicyRequirement {
              Text(requirement)
                .font(.caption).foregroundStyle(.secondary)
            }
            if let checkedAt = store.profileCheckedAt {
              HStack(spacing: 4) {
                Text("Last checked")
                Text(checkedAt, style: .time)
              }
              .font(.caption).foregroundStyle(.secondary)
            }
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        GroupBox("Finish in System Settings") {
          VStack(alignment: .leading, spacing: 18) {
            step(
              1, title: "Save your feature choices",
              detail:
                "Saving applies local preferences and generates the profile. Model files are handled separately."
            )
            step(
              2, title: "Review and install the profile",
              detail:
                "Choose Install Profile, then complete installation in System Settings. Opening the installer does not install it."
            )
            step(
              3, title: "Refresh the installation status",
              detail:
                "Use Refresh after installation. Replace the profile whenever you change a feature, including when you make it unmanaged."
            )
          }
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        Text(
          "MDM declarations are also generated alongside the policy for features that require device management. They are not an installable configuration profile."
        )
        .font(.callout).foregroundStyle(.secondary)
        DiagnosticsDisclosure(text: store.lastDiagnostics)
      }
      .padding(28).frame(maxWidth: 800, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private func step(_ number: Int, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(String(number)).font(.headline).foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(.quaternary, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).fontWeight(.medium)
        Text(detail).font(.callout).foregroundStyle(.secondary)
      }
    }
  }
}
