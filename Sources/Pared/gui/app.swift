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
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…", action: updates.check)
          .disabled(!updates.canCheck || store.working || store.hasChanges)
        Button("Changelog") { store.section = .updates }
      }
      CommandGroup(replacing: .newItem) {
        Button("Open Settings File…", action: store.choosePolicy)
          .keyboardShortcut("o")
          .disabled(store.working)
        Button("Use Default Settings", action: store.useDefaultPolicy)
          .disabled(store.working || store.policyURL == Policy.defaultURL)
      }
      CommandGroup(replacing: .saveItem) {
        Button("Save Changes", action: store.save)
          .keyboardShortcut("s")
          .disabled(!store.canSave)
        Button("Discard Changes", action: store.discardChanges)
          .disabled(store.working || !store.hasChanges)
        Button("Review Changes", action: store.showChanges)
          .disabled(!store.hasChanges)
        Divider()
        Button("Export Profile…", action: store.exportProfile)
          .disabled(!store.canUseSavedPolicy)
      }
      CommandMenu("Actions") {
        Button("Refresh Status", action: store.refresh)
          .keyboardShortcut("r")
          .disabled(store.working)
        Button("Install Profile…", action: store.openProfile)
          .keyboardShortcut("i", modifiers: [.command, .shift])
          .disabled(!store.canUseSavedPolicy)
        Button("Review Model Removal…", action: store.reviewCleanup)
          .disabled(!store.canUseSavedPolicy || store.cleanupTargets.isEmpty)
      }
      CommandGroup(after: .sidebar) {
        ForEach(GUISection.allCases.enumerated(), id: \.element) { index, section in
          Button("Show \(section.rawValue)") { store.section = section }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
      }
      CommandGroup(replacing: .help) {
        Link("Pared Help", destination: URL(string: "https://github.com/4evy/pared#use")!)
        Button("Changelog") { store.section = .updates }
      }
    }
  }
}

struct ParedWindow: View {
  @Bindable var store: GUIStore
  @Bindable var updates: GUIUpdater

  var body: some View {
    NavigationSplitView {
      List(selection: $store.section) {
        Label(GUISection.overview.rawValue, systemImage: GUISection.overview.symbol)
          .tag(GUISection.overview)
        Section("Customize") {
          ForEach([GUISection.features, .models, .profile]) { section in
            Label(section.rawValue, systemImage: section.symbol).tag(section)
          }
        }
        Section {
          Label(GUISection.updates.rawValue, systemImage: GUISection.updates.symbol)
            .tag(GUISection.updates)
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
            let on = store.features.count { store.draft.state($0.id) == .enabled }
            let off = store.features.count { store.draft.state($0.id) == .disabled }
            let defaults = store.features.count { store.draft.state($0.id) == .unmanaged }
            Text("\(on) on · \(off) off · \(defaults) default")
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
              Button("Show \(destination.rawValue)") { store.section = destination }
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
            ProgressView().controlSize(.small)
            Text(store.activity)
          } else {
            Image(systemName: store.hasChanges ? "pencil.circle" : "doc")
              .accessibilityHidden(true)
            if store.hasChanges {
              Button(
                "Review \(store.changedNames.count) unsaved changes", action: store.showChanges
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
              Button("Open Settings File…", action: store.choosePolicy)
                .disabled(store.working)
              Button("Use Default Settings", action: store.useDefaultPolicy)
                .disabled(store.working || store.policyURL == Policy.defaultURL)
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
            Button("Refresh", systemImage: "arrow.clockwise", action: store.refresh)
              .labelStyle(.iconOnly).help("Refresh status (⌘R)")
              .disabled(store.working)
          }
        }
        if store.section != .updates && (store.section != .overview || store.hasChanges) {
          ToolbarItem {
            Button(store.policyExists ? "Save Changes" : "Save Choices", action: store.save)
              .buttonStyle(.borderedProminent)
              .disabled(!store.canSave)
              .help("Save your choices and apply local settings (⌘S)")
          }
        }
      }
    }
    .frame(minWidth: 880, minHeight: 580)
    .onChange(of: store.working) { _, _ in updates.resumeIfReady() }
    .onChange(of: store.hasChanges) { _, _ in updates.resumeIfReady() }
    .alert(item: $store.issue) { issue in
      Alert(
        title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
    }
    .sheet(item: $store.cleanupReview) { review in
      CleanupReview(store: store, review: review)
    }
    .sheet(item: $store.modelQuitReview) { review in
      ModelQuitReview(store: store, review: review)
    }
    .sheet(item: $store.quickActionReview) { action in
      QuickActionReview(store: store, action: action)
    }
  }
}

struct InlineMessage: View {
  let title: String?
  let message: String
  let symbol: String
  var isError = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        if let title { Text(title).fontWeight(.medium).accessibilityAddTraits(.isHeader) }
        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .font(.callout)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5))
  }
}

struct PageHeading: View {
  let title: String
  let description: String
  let symbol: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(.tint)
        .frame(width: 48, height: 48)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if !description.isEmpty {
          Text(description).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.bottom, 8)
  }
}

struct DiagnosticsDisclosure: View {
  let text: String

  var body: some View {
    if !text.isEmpty {
      DisclosureGroup("Operation Details") {
        ScrollView {
          Text(text).font(.caption.monospaced()).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180).padding(.top, 8)
      }
    }
  }
}
