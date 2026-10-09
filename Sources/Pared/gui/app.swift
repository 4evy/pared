import AppKit
import SwiftUI

@MainActor
final class GUIAppDelegate: NSObject, NSApplicationDelegate {
  weak var store: GUIStore?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Load the current artwork explicitly for both app and CLI launches
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
      ?? Bundle.module.url(forResource: "icon", withExtension: "png"),
      let icon = NSImage(contentsOf: url)
    {
      NSApplication.shared.applicationIconImage = icon
    }
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if store?.busy == true {
      let alert = NSAlert()
      alert.messageText = "An operation is still running"
      alert.informativeText = "Wait for the operation to finish before quitting Pared."
      alert.addButton(withTitle: "Keep Open")
      alert.runModal()
      return .terminateCancel
    }
    return store?.confirmDiscardIfNeeded() == false ? .terminateCancel : .terminateNow
  }
}

struct ParedApp: App {
  @MainActor static var initialPolicyURL: URL?
  @NSApplicationDelegateAdaptor(GUIAppDelegate.self) private var delegate
  @State private var store = GUIStore(policyURL: initialPolicyURL)
  @State private var updates = GUIUpdater()

  var body: some Scene {
    Window("Pared", id: "main") {
      ParedWindow(store: store, updates: updates)
        .task {
          delegate.store = store
          if !store.loaded { store.refresh() }
          updates.start(store: store)
        }
    }
    .defaultSize(width: 1120, height: 760)
    .commands { GUICommands(store: store, updates: updates) }
  }
}

struct ParedWindow: View {
  @Bindable var store: GUIStore
  @Bindable var updates: GUIUpdater

  var body: some View {
    NavigationSplitView {
      List(selection: $store.section) {
        ForEach(GUISidebarGroup.allCases) { group in
          if group == .primary {
            sidebarRows(group)
          } else {
            Section {
              sidebarRows(group)
            } header: {
              if let title = group.title { Text(title) }
            }
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 240)
      .listStyle(.sidebar)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          Label(store.policyStateTitle, systemImage: store.readOnly ? "lock" : "doc")
            .font(.callout.weight(.medium))
            .help(store.policyURL.path)
          if store.loaded && (store.policyExists || store.hasChanges) {
            Text(store.choiceCounts.map(\.summary).joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    } detail: {
      VStack(spacing: 0) {
        if let error = store.policyError {
          InlineMessage(
            title: "Settings unavailable", message: error,
            symbol: "exclamationmark.triangle", isError: true)
        }
        if let notice = store.notice {
          HStack(spacing: 12) {
            InlineMessage(title: nil, message: notice, symbol: "info.circle")
            if let destination = store.noticeDestination, destination != store.section {
              GUIActionButton(store: store, action: .show(destination))
            }
            Button("Dismiss", systemImage: "xmark", action: store.dismissNotice)
              .labelStyle(.iconOnly).buttonStyle(.borderless).help("Dismiss message")
          }
          .padding(.trailing, 14)
        }
        if store.readOnly {
          InlineMessage(
            title: "Managed by Nix",
            message:
              "Change programs.pared.features in your Nix configuration and rebuild. You can inspect models and install this policy’s profile here.",
            symbol: "lock")
        }
        Group {
          switch store.section ?? .overview {
          case .overview: OverviewPane(store: store)
          case .features: FeaturesPane(store: store)
          case .models: ModelsPane(store: store)
          case .profile: ProfilePane(store: store)
          case .updates: UpdatesPane(updates: updates, store: store)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        HStack(spacing: 10) {
          if store.working {
            ProgressView().controlSize(.small).accessibilityLabel(store.activity)
            Text(store.activity)
              .accessibilityHidden(true)
          } else {
            Image(systemName: store.hasChanges ? "pencil.circle" : "doc")
              .accessibilityHidden(true)
            if store.hasChanges {
              GUIActionButton(
                store: store, action: .reviewChanges,
                title: "Review \(store.changedNames.count) unsaved changes"
              )
              .buttonStyle(.link)
            } else {
              Text(
                store.policyExists
                  ? "All choices saved" : "Draft choices · save to apply")
            }
          }
          Spacer(minLength: 20)
          if store.section != .updates {
            Menu {
              Text(store.policyURL.path)
              ForEach(GUIAction.settings) { action in
                GUIActionButton(store: store, action: action)
              }
            } label: {
              Label("Settings File", systemImage: "folder")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(store.policyURL.path)
          }
        }
        .font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
      }
      .navigationTitle((store.section ?? .overview).rawValue)
      .toolbar {
        if store.section != .updates {
          ToolbarItem {
            GUIActionButton(
              store: store, action: .refresh, title: "Refresh", symbol: "arrow.clockwise"
            )
            .labelStyle(.iconOnly).help("Refresh status (⌘R)")
          }
        }
        if store.hasChanges || (!store.policyExists && store.section != .updates) {
          ToolbarItem(placement: .primaryAction) {
            GUIActionButton(store: store, action: .save)
              .buttonStyle(.borderedProminent)
              .help("Save your choices and apply local settings (⌘S)")
          }
        }
      }
    }
    .frame(minWidth: 720, minHeight: 540)
    .onChange(of: store.working) { _, _ in updates.resumeIfReady() }
    .onChange(of: store.hasChanges) { _, _ in updates.resumeIfReady() }
    .alert(item: $store.issue) { issue in
      Alert(
        title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
    }
    .sheet(item: $store.review) { review in
      GUIReviewView(store: store, review: review)
    }
  }

  private func sidebarRows(_ group: GUISidebarGroup) -> some View {
    ForEach(group.sections) { section in
      Label(section.rawValue, systemImage: section.symbol).tag(section)
    }
  }
}
