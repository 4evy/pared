import AppKit
import SwiftUI

@MainActor
final class GUIAppDelegate: NSObject, NSApplicationDelegate {
  weak var store: GUIStore?

  func applicationDidFinishLaunching(_ notification: Notification) {
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
  @NSApplicationDelegateAdaptor(GUIAppDelegate.self) private var delegate
  @State private var store = GUIStore()

  var body: some Scene {
    Window("Features", id: "main") {
      ParedWindow(store: store)
        .task {
          delegate.store = store
          if !store.loaded { store.refresh() }
        }
    }
    .defaultSize(width: 1120, height: 760)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Open Policy…", action: store.choosePolicy)
          .keyboardShortcut("o")
          .disabled(store.working)
        Button("Use Default Policy", action: store.useDefaultPolicy)
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
      CommandMenu("Policy") {
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
        ForEach(Array(GUISection.allCases.enumerated()), id: \.element) { index, section in
          Button("Show \(section.rawValue)") { store.section = section }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
      }
      CommandGroup(replacing: .help) {
        Link("Pared Help", destination: URL(string: "https://github.com/4evy/pared#use")!)
      }
    }
  }
}

struct ParedWindow: View {
  @Bindable var store: GUIStore

  var body: some View {
    NavigationSplitView {
      List(GUISection.allCases, selection: $store.section) { section in
        Label(section.rawValue, systemImage: section.symbol)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 240)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          Label(store.policyStateTitle, systemImage: store.readOnly ? "lock" : "doc")
            .font(.callout.weight(.medium))
          if store.loaded {
            Text("Your choices").font(.caption).foregroundStyle(.secondary)
            ForEach([FeatureState.enabled, .disabled, .unmanaged], id: \.self) { state in
              let count = store.features.filter { store.draft.state($0.id) == state }.count
              Text("\(count) \(state.title.lowercased())")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    } detail: {
      VStack(spacing: 0) {
        if let error = store.policyError {
          InlineMessage(
            title: "Policy unavailable", message: error,
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
        if store.loaded && !store.policyExists {
          InlineMessage(
            title: "Review your first policy",
            message:
              "Every feature starts disabled. Nothing changes until you save. Review your choices before choosing Save Policy.",
            symbol: "switch.2")
        }
        if store.readOnly {
          InlineMessage(
            title: "Managed by Nix",
            message:
              "Change programs.pared.features in your Nix configuration and rebuild. You can inspect models and install this policy’s profile here.",
            symbol: "lock")
        }
        Group {
          switch store.section ?? .features {
          case .features: FeaturesPane(store: store)
          case .models: ModelsPane(store: store)
          case .profile: ProfilePane(store: store)
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
            if store.hasChanges {
              Button(
                "Review \(store.changedNames.count) unsaved changes", action: store.showChanges
              )
              .buttonStyle(.link)
            } else {
              Text(store.policyExists ? "No pending changes" : "Policy not saved")
            }
          }
          Spacer(minLength: 20)
          Text(
            store.policyURL.path.replacingOccurrences(
              of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
          )
          .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
          .help(store.policyURL.path)
        }
        .font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
      }
      .navigationTitle((store.section ?? .features).rawValue)
      .toolbar {
        ToolbarItem {
          Button("Refresh", systemImage: "arrow.clockwise", action: store.refresh)
            .labelStyle(.iconOnly).help("Refresh status (⌘R)")
            .disabled(store.working)
        }
        ToolbarItem {
          Button(store.policyExists ? "Save Changes" : "Save Policy", action: store.save)
            .buttonStyle(.borderedProminent)
            .disabled(!store.canSave)
            .help("Save policy and apply local preferences (⌘S)")
        }
      }
    }
    .frame(minWidth: 880, minHeight: 580)
    .alert(item: $store.issue) { issue in
      Alert(
        title: Text(issue.title), message: Text(issue.message), dismissButton: .default(Text("OK")))
    }
    .sheet(
      isPresented: Binding(
        get: { store.cleanupReview != nil },
        set: { if !$0 { store.cleanupReview = nil } }
      )
    ) {
      CleanupReview(store: store)
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
      VStack(alignment: .leading, spacing: 3) {
        if let title { Text(title).fontWeight(.medium) }
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
      Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tint)
        .frame(width: 40).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.title2.bold())
        Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
