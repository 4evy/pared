import AppKit
import Observation
import UniformTypeIdentifiers

struct GUIIssue: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

@MainActor
@Observable
final class GUIStore {
  let catalog: Catalog?
  private let runner: GUICommandRunner
  var section: GUISection? = .features
  var selectedFeature: String? = "writingTools"
  var selectedModel: String? = "com.apple.modelcatalog"
  var search = ""
  var featureFilter: GUIFeatureFilter = .all
  var policyURL = Policy.defaultURL
  private(set) var policy = Policy()
  var draft = Policy()
  private(set) var policyExists = false
  private(set) var loaded = false
  private(set) var busy = false
  private(set) var refreshing = false
  private(set) var activity = ""
  private(set) var notice: String?
  private(set) var noticeDestination: GUISection?
  private(set) var policyError: String?
  private(set) var statusError: String?
  private(set) var profileError: String?
  private(set) var modelsError: String?
  private(set) var featureStatuses: [String: GUIFeatureStatus] = [:]
  private(set) var modelStatuses: [GUIModelStatus] = []
  private(set) var profileStatus: GUIProfileStatus?
  private(set) var profileCheckedAt: Date?
  private(set) var modelsCheckedAt: Date?
  private(set) var profileNeedsReplacement = false
  private(set) var lastDiagnostics = ""
  var issue: GUIIssue?
  var cleanupReview: [String]?

  init() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.count == 3, arguments[0] == "gui", arguments[1] == "--policy" {
      policyURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    }
    runner = GUICommandRunner(
      executable: Bundle.main.executableURL
        ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    do {
      catalog = try Catalog.load()
    } catch {
      catalog = nil
      policyError = String(describing: error)
    }
  }

  var features: [FeaturePresentation] {
    (catalog?.features.keys.sorted() ?? []).map(FeaturePresentation.init)
  }

  var changedNames: [String] {
    features.map(\.id).filter { draft.state($0) != policy.state($0) }
  }

  var hasChanges: Bool { !changedNames.isEmpty }

  var working: Bool { busy || refreshing }

  var policyStateTitle: String {
    if policyError != nil { return "Policy unavailable" }
    if !loaded { return "Loading policy…" }
    if readOnly { return "Managed by Nix" }
    if !policyExists { return "New policy" }
    return hasChanges ? "Unsaved choices" : "Saved policy"
  }

  var savedPolicyRequirement: String? {
    if policyError != nil { return "Open a valid policy to continue." }
    if !loaded { return "Loading your policy…" }
    if busy { return "Wait for the current operation to finish." }
    if refreshing { return "Checking the current status…" }
    if !policyExists { return "Save your first policy to continue." }
    if hasChanges { return "Save or discard your pending changes first." }
    return nil
  }

  var filteredFeatures: [FeaturePresentation] {
    features.filter { feature in
      let matchesSearch =
        search.isEmpty
        || feature.title.localizedCaseInsensitiveContains(search)
        || (catalog?.features[feature.id]?.description.localizedCaseInsensitiveContains(search)
          == true)
        || feature.id.localizedCaseInsensitiveContains(search)
      let matchesFilter: Bool
      switch featureFilter {
      case .all: matchesFilter = true
      case .enabled: matchesFilter = draft.state(feature.id) == .enabled
      case .disabled: matchesFilter = draft.state(feature.id) == .disabled
      case .unmanaged: matchesFilter = draft.state(feature.id) == .unmanaged
      case .changes: matchesFilter = changedNames.contains(feature.id)
      }
      return matchesSearch && matchesFilter
    }
  }

  func selectVisibleFeature() {
    if !filteredFeatures.contains(where: { $0.id == selectedFeature }) {
      selectedFeature = filteredFeatures.first?.id
    }
  }

  func showChanges() {
    section = .features
    search = ""
    featureFilter = .changes
    selectVisibleFeature()
  }

  func dismissNotice() {
    notice = nil
    noticeDestination = nil
  }

  var readOnly: Bool {
    policyURL.resolvingSymlinksInPath().path.hasPrefix("/nix/store/")
  }

  var canSave: Bool {
    loaded && policyError == nil && !working && !readOnly && (hasChanges || !policyExists)
  }

  var canUseSavedPolicy: Bool {
    loaded && policyError == nil && !working && !hasChanges && policyExists
  }

  var cleanupTargets: [String] {
    guard let catalog else { return [] }
    return policy.cleanupTargets(catalog)
  }

  func setAll(_ state: FeatureState) {
    guard loaded, !busy, !readOnly else { return }
    for feature in features { draft.features[feature.id] = state }
  }

  func refresh() {
    guard !working, catalog != nil else { return }
    refreshing = true
    activity = "Checking settings…"
    Task {
      await reload(replaceDraft: !hasChanges)
      refreshing = false
    }
  }

  private func reload(replaceDraft: Bool) async {
    guard let catalog else { return }
    do {
      let current = try Policy.load(
        policyURL, explicit: policyURL != Policy.defaultURL, catalog: catalog)
      if replaceDraft {
        policy = current
        draft = current
        policyExists = FileManager.default.fileExists(atPath: policyURL.path)
      }
      policyError = nil
      loaded = true
    } catch {
      policyError = String(describing: error)
      loaded = false
      featureStatuses = [:]
      modelStatuses = []
      profileStatus = nil
      return
    }
    // Read an unsaved default policy without creating it on first launch
    let queryURL: URL? = policyExists || policyURL != Policy.defaultURL ? policyURL : nil
    do {
      let result = try await runner.run(["status"], policyURL: queryURL)
      try result.requireSuccess()
      featureStatuses = try result.decode([String: GUIFeatureStatus].self)
      statusError = nil
    } catch {
      featureStatuses = [:]
      statusError = String(describing: error)
    }
    activity = "Checking profile…"
    do {
      let result = try await runner.run(["profile", "status"], policyURL: queryURL)
      // An absent profile exits 1 with valid JSON; query failures have no status
      if result.output.isEmpty { try result.requireSuccess() }
      profileStatus = try result.decode(GUIProfileStatus.self)
      profileError = nil
    } catch {
      profileStatus = nil
      profileError = String(describing: error)
    }
    profileCheckedAt = Date()
    activity = "Checking models…"
    do {
      let result = try await runner.run(["models", "status"], policyURL: queryURL)
      if result.output.isEmpty { try result.requireSuccess() }
      modelStatuses = try result.decode([GUIModelStatus].self)
      modelsError = nil
    } catch {
      modelStatuses = []
      modelsError = String(describing: error)
    }
    modelsCheckedAt = Date()
  }

  private func verifyPolicyUnchanged() throws {
    guard let catalog, loaded, policyError == nil else {
      throw CLIError("Load a valid policy before continuing")
    }
    let exists = FileManager.default.fileExists(atPath: policyURL.path)
    let current = try Policy.load(
      policyURL, explicit: policyURL != Policy.defaultURL, catalog: catalog)
    guard exists == policyExists, try jsonData(current) == jsonData(policy) else {
      throw CLIError(
        "This policy changed outside the app. Discard your pending edits and refresh before continuing."
      )
    }
  }

  func save() {
    guard canSave else { return }
    let names = policyExists ? changedNames : features.map(\.id)
    let requested = draft
    busy = true
    activity = "Saving settings…"
    notice = nil
    Task {
      var diagnostics: [String] = []
      var beganSaving = false
      do {
        try verifyPolicyUnchanged()
        for (state, command) in [
          (FeatureState.enabled, "enable"), (.disabled, "disable"), (.unmanaged, "reset"),
        ] {
          let selected = names.filter { requested.state($0) == state }
          guard !selected.isEmpty else { continue }
          beganSaving = true
          let result = try await runner.run([command] + selected, policyURL: policyURL)
          diagnostics.append(result.diagnostics)
          try result.requireSuccess()
        }
        profileNeedsReplacement = true
        notice =
          "Settings saved. Install the updated profile to enforce managed controls and block downloads."
        noticeDestination = .profile
        lastDiagnostics = diagnostics.joined(separator: "\n\n")
        await reload(replaceDraft: true)
      } catch {
        lastDiagnostics = diagnostics.joined(separator: "\n\n")
        issue = GUIIssue(
          title: "Settings could not be fully saved",
          message: String(describing: error)
            + (beganSaving
              ? "\n\nEarlier changes may have succeeded. Check the saved policy before retrying."
              : ""))
        if beganSaving {
          profileNeedsReplacement = true
          await reload(replaceDraft: true)
          draft = requested
        }
      }
      busy = false
    }
  }

  func discardChanges() {
    guard !working else { return }
    draft = policy
    refresh()
  }

  func choosePolicy() {
    guard !working else { return }
    let panel = NSOpenPanel()
    panel.title = "Open Policy"
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    switchPolicy(to: url)
  }

  func useDefaultPolicy() {
    guard !working else { return }
    switchPolicy(to: Policy.defaultURL)
  }

  private func switchPolicy(to url: URL) {
    guard url != policyURL, confirmDiscardIfNeeded() else { return }
    policyURL = url
    policy = Policy()
    draft = policy
    loaded = false
    policyExists = false
    featureStatuses = [:]
    modelStatuses = []
    profileStatus = nil
    profileCheckedAt = nil
    modelsCheckedAt = nil
    featureFilter = .all
    search = ""
    statusError = nil
    modelsError = nil
    profileError = nil
    profileNeedsReplacement = false
    lastDiagnostics = ""
    notice = nil
    noticeDestination = nil
    refresh()
  }

  func confirmDiscardIfNeeded() -> Bool {
    guard hasChanges else { return true }
    let alert = NSAlert()
    alert.messageText = "Discard unsaved changes?"
    alert.informativeText = "Your feature choices have not been saved."
    alert.addButton(withTitle: "Keep Editing")
    alert.addButton(withTitle: "Discard Changes")
    return alert.runModal() == .alertSecondButtonReturn
  }

  func openProfile() {
    guard canUseSavedPolicy else { return }
    perform(
      title: "Opening profile installer…", arguments: ["profile", "open"],
      success:
        "Finish installing the profile in System Settings, then refresh to check its installation.")
  }

  func exportProfile() {
    guard canUseSavedPolicy, let catalog else { return }
    let panel = NSSavePanel()
    panel.title = "Export Configuration Profile"
    panel.nameFieldStringValue = Artifacts.profileFilename
    panel.allowedContentTypes = [UTType(filenameExtension: "mobileconfig") ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try verifyPolicyUnchanged()
      guard url.resolvingSymlinksInPath() != policyURL.resolvingSymlinksInPath() else {
        throw CLIError("Choose a different destination to preserve your policy file.")
      }
      try profileData(policy: policy, catalog: catalog).write(to: url, options: .atomic)
      notice = "Profile exported. Install it in System Settings to apply its controls."
      noticeDestination = .profile
    } catch {
      issue = GUIIssue(title: "Profile could not be exported", message: String(describing: error))
    }
  }

  func reviewCleanup() {
    guard canUseSavedPolicy, !cleanupTargets.isEmpty else { return }
    busy = true
    activity = "Preparing removal preview…"
    Task {
      do {
        try verifyPolicyUnchanged()
        let result = try await runner.run(
          ["models", "cleanup", "--dry-run"], policyURL: policyURL)
        try result.requireSuccess()
        let targets = try result.decode([String].self)
        guard targets == cleanupTargets else {
          throw CLIError("The removal preview changed. Refresh and review it again.")
        }
        cleanupReview = targets
      } catch {
        issue = GUIIssue(title: "Removal preview unavailable", message: String(describing: error))
      }
      busy = false
    }
  }

  func removeReviewedModels() {
    guard canUseSavedPolicy, let reviewed = cleanupReview, !reviewed.isEmpty else { return }
    cleanupReview = nil
    guard reviewed == cleanupTargets else {
      issue = GUIIssue(
        title: "Removal preview changed", message: "Review the model selection again.")
      return
    }
    perform(
      title: "Requesting model removal…", arguments: ["models", "cleanup"],
      success:
        "The removal request returned successfully. Refresh the snapshots and check free space to assess the result.",
      reviewedTargets: reviewed
    )
  }

  func download(_ name: String) {
    guard canUseSavedPolicy, policy.state(name) == .enabled,
      catalog?.features[name]?.recovery != nil
    else { return }
    perform(
      title: "Requesting download…", arguments: ["models", "download", name],
      success:
        "Apple accepted the download request. The download continues in the background; refresh to check a new snapshot."
    )
  }

  private func perform(
    title: String, arguments: [String], success: String, reviewedTargets: [String]? = nil
  ) {
    busy = true
    activity = title
    notice = nil
    Task {
      do {
        try verifyPolicyUnchanged()
        let result: GUICommandResult
        if let reviewedTargets {
          result = try await runner.cleanup(
            reviewedTargets: reviewedTargets, policyData: jsonData(policy), policyURL: policyURL)
        } else {
          result = try await runner.run(arguments, policyURL: policyURL)
        }
        lastDiagnostics = result.diagnostics
        try result.requireSuccess()
        notice = success
        noticeDestination = arguments.first == "models" ? .models : .profile
      } catch {
        issue = GUIIssue(
          title: "Operation could not be completed", message: String(describing: error))
      }
      await reload(replaceDraft: true)
      busy = false
    }
  }
}
