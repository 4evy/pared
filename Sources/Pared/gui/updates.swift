import Foundation
import SwiftUI

/// App targets supply their updater without adding its runtime to the CLI
@MainActor
public protocol ParedUpdateControlling: AnyObject {
  var canCheckForUpdates: Bool { get }
  var automaticallyChecksForUpdates: Bool { get set }
  var automaticallyDownloadsUpdates: Bool { get set }
  var lastUpdateCheckDate: Date? { get }
  func start(
    readiness: @escaping @MainActor () -> Bool,
    stateChanged: @escaping @MainActor () -> Void
  ) throws
  func checkForUpdates()
  func resumeIfReady()
}

@MainActor
@Observable
final class GUIUpdater {
  private var controller: (any ParedUpdateControlling)?
  private var started = false
  private(set) var unavailableReason: String?
  private(set) var canCheck = false
  private(set) var automaticChecks = false
  private(set) var automaticDownloads = false
  private(set) var lastChecked: Date?

  var available: Bool { controller != nil }

  var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development build"
  }

  func start(store: GUIStore) {
    guard !started else { return }
    started = true
    guard Bundle.main.bundleURL.pathExtension == "app",
      !Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/nix/store/")
    else {
      unavailableReason = "Update this installation with the package manager or build you used."
      return
    }
    do {
      guard let loaded = ParedMain.updateController else {
        unavailableReason =
          "This build does not include the updater. Download the Finder app to use app updates."
        return
      }
      try loaded.start(
        readiness: { [weak store] in
          guard let store else { return false }
          return !store.working && !store.hasChanges
        },
        stateChanged: { [weak self] in self?.refresh() })
      controller = loaded
      refresh()
    } catch {
      unavailableReason = "Updates unavailable: \(error.localizedDescription)"
    }
  }

  private func refresh() {
    guard let controller else { return }
    canCheck = controller.canCheckForUpdates
    automaticChecks = controller.automaticallyChecksForUpdates
    automaticDownloads = controller.automaticallyDownloadsUpdates
    lastChecked = controller.lastUpdateCheckDate
  }

  func check() { controller?.checkForUpdates() }
  func resumeIfReady() { controller?.resumeIfReady() }

  func setAutomaticChecks(_ enabled: Bool) {
    controller?.automaticallyChecksForUpdates = enabled
    refresh()
  }

  func setAutomaticDownloads(_ enabled: Bool) {
    controller?.automaticallyDownloadsUpdates = enabled
    refresh()
  }
}

struct UpdatesPane: View {
  @Bindable var updates: GUIUpdater
  @Bindable var store: GUIStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        PageHeading(
          title: "Updates & Changelog",
          description: "Keep Pared up to date and see what’s changed.",
          symbol: "arrow.down.circle")
        GroupBox("Pared \(updates.version)") {
          VStack(alignment: .leading, spacing: 12) {
            if updates.available {
              // Swift 6.2.4 crashes on actor-isolated method references in
              // Binding
              Toggle(
                "Automatically check for updates",
                isOn: Binding(
                  get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
              Toggle(
                "Download and install updates automatically",
                isOn: Binding(
                  get: { updates.automaticDownloads }, set: { updates.setAutomaticDownloads($0) })
              )
              .disabled(!updates.automaticChecks)
              Text("Updates are checked daily. Automatic installation happens when you quit Pared.")
                .font(.callout).foregroundStyle(.secondary)
              if store.working || store.hasChanges {
                Text(
                  "Finish the current operation and save or discard your changes before updating."
                )
                .font(.callout).foregroundStyle(.secondary)
              }
              HStack {
                Button("Check for Updates…", action: updates.check)
                  .disabled(!updates.canCheck || store.working || store.hasChanges)
                if let checked = updates.lastChecked {
                  Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
            } else {
              Text(updates.unavailableReason ?? "Starting the updater…")
                .foregroundStyle(.secondary).textSelection(.enabled)
            }
            Link(
              "Published Releases",
              destination: URL(string: "https://github.com/4evy/pared/releases")!)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        ChangelogView()
      }
      .padding(28).frame(maxWidth: 860, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }
}

private struct ChangelogView: View {
  private let blocks: [ChangelogBlock] = {
    guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
      let source = try? String(contentsOf: url, encoding: .utf8),
      let markdown = try? AttributedString(markdown: source)
    else { return [] }
    return markdown.runs[\.presentationIntent].compactMap { intent, range in
      guard let intent, let identity = intent.components.first?.identity else { return nil }
      let content = AttributedString(markdown[range])
      let headingLevel = intent.components.compactMap { component -> Int? in
        guard case .header(let level) = component.kind else { return nil }
        return level
      }.first
      if headingLevel == 1, String(content.characters) == "Changelog" { return nil }
      let ordinal = intent.components.compactMap { component -> Int? in
        guard case .listItem(let ordinal) = component.kind else { return nil }
        return ordinal
      }.first
      let marker = ordinal.map {
        intent.components.contains { $0.kind == .unorderedList } ? "•" : "\($0)."
      }
      return ChangelogBlock(
        id: identity, content: content, headingLevel: headingLevel, marker: marker)
    }
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Changelog").font(.title2.bold()).accessibilityAddTraits(.isHeader)
      Text("Included with this build; Unreleased entries describe development changes.")
        .font(.callout).foregroundStyle(.secondary)
      if blocks.isEmpty {
        Text("The changelog is not bundled with this build.").foregroundStyle(.secondary)
      }
      ForEach(blocks) { block in
        if block.headingLevel == 2 {
          Divider().padding(.top, 8)
          Text(block.content).font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
        } else if block.headingLevel != nil {
          Text(block.content).font(.headline).padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
        } else if let marker = block.marker {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker).accessibilityHidden(true)
            Text(block.content)
          }
        } else {
          Text(block.content)
        }
      }
      Link(
        "Full Changelog on GitHub",
        destination: URL(string: "https://github.com/4evy/pared/blob/master/CHANGELOG.md")!
      )
      .padding(.top, 8)
    }
    .textSelection(.enabled)
  }

}

private struct ChangelogBlock: Identifiable {
  let id: Int
  let content: AttributedString
  let headingLevel: Int?
  let marker: String?
}
