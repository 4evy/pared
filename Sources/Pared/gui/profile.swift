import SwiftUI

struct ProfilePane: View {
  @Bindable var store: GUIStore

  private let instructions: [(title: String, detail: String)] = [
    (
      "Save your feature choices",
      "Saving applies local preferences and generates the profile. Model files are handled separately."
    ),
    (
      "Review and install the profile",
      "Choose Install Profile, then complete installation in System Settings. Opening the installer does not install it."
    ),
    (
      "Refresh the installation status",
      "Use Refresh after installation. Replace the profile whenever you change a feature, including when you make it unmanaged."
    ),
  ]

  var body: some View {
    GUIPage {
      PageHeading(
        title: "Finish Setup",
        description:
          "A profile enforces supported feature controls and blocks downloads for models your policy disables.",
        symbol: "doc.badge.gearshape")
      SettingsGroup(title: "Installation") {
        if let status = store.profileStatus {
          Label(
            status.installed ? "Pared profile installed" : "Pared profile not installed",
            systemImage: status.installed ? "checkmark.seal" : "doc.badge.plus"
          )
          .font(.headline)
          if status.installed {
            Text(
              "macOS reports a Pared profile installed. Install it again after changing your choices so it stays up to date."
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
          GUIActionButton(store: store, action: .refresh, title: "Check Again")
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
          GUIActionButton(store: store, action: .installProfile)
            .buttonStyle(.borderedProminent)
          GUIActionButton(store: store, action: .exportProfile, title: "Export…")
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
      SettingsGroup(title: "Finish in System Settings", spacing: 18) {
        ForEach(instructions.enumerated(), id: \.offset) { index, instruction in
          step(index + 1, title: instruction.title, detail: instruction.detail)
        }
      }
      DisclosureGroup("Advanced Details") {
        VStack(alignment: .leading, spacing: 8) {
          if let status = store.profileStatus, status.installed {
            Text("\(status.installedPayloadCount) profile payloads reported.")
          }
          Text(
            "Installed metadata does not confirm the contents match your saved choices or prove runtime enforcement."
          )
          Text(
            "Apple deprecated the legacy AI restrictions in macOS 26.4. Their replacement declarations require supervised MDM enrollment. Pared generates these alongside your settings; they are not an installable profile. Forced preferences and model download blocks are separate from those restrictions."
          )
        }
        .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
      }
      DiagnosticsDisclosure(text: store.lastDiagnostics)
    }
  }

  private func step(_ number: Int, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(String(number)).font(.headline).foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(.quaternary, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).fontWeight(.medium).accessibilityAddTraits(.isHeader)
        Text(detail).font(.callout).foregroundStyle(.secondary)
      }
    }
  }
}
