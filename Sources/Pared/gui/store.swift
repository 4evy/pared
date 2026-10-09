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
  var section: GUISection? = .overview
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
  private(set) var featureStatuses: [String: FeatureStatus] = [:]
  private(set) var modelStatuses: [String: ModelStatus] = [:]
  private(set) var profileStatus: ProfileInstallationStatus?
  private(set) var profileCheckedAt: Date?
  private(set) var modelsCheckedAt: Date?
  private(set) var profileNeedsReplacement = false
  private(set) var lastDiagnostics = ""
  var issue: GUIIssue?
  var cleanupReview: ModelCleanupOffer?
  var modelQuitReview: ModelQuitOffer?
  var quickActionReview: GUIQuickAction?
  private(set) var downloadPreparation: String?

  init(policyURL: URL? = nil) {
    if let policyURL { self.policyURL = policyURL.standardizedFileURL }
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
    catalog?.presentations ?? []
  }

  func presentation(_ name: String) -> FeaturePresentation {
    catalog?.presentation(name) ?? FeaturePresentation(name)
  }

  func modelTitle(_ assetSet: String) -> String { catalog?.modelTitle(assetSet) ?? assetSet }

  var changedNames: [String] {
    guard let catalog else { return [] }
    return draft.changedFeatureNames(from: policy, in: catalog)
  }

  var hasChanges: Bool { !changedNames.isEmpty }

  var working: Bool { busy || refreshing }

  var canEditChoices: Bool {
    loaded && policyError == nil && !working && !readOnly
  }

  var downloadFeatures: [FeaturePresentation] {
    features.filter { catalog?.features[$0.id]?.recovery != nil }
      .sorted(
        using: KeyPathComparator(\.title, comparator: String.StandardComparator.localizedStandard))
  }

  func reviewQuickAction(_ action: GUIQuickAction) {
    guard canEditChoices else { return }
    quickActionReview = action
  }

  func confirmQuickAction() {
    guard canEditChoices, let action = quickActionReview else { return }
    quickActionReview = nil
    switch action {
    case .turnOffAll, .turnOffAndRemoveAll:
      downloadPreparation = nil
      setAll(.disabled)
    case .enableFeature(let name):
      guard catalog?.features[name]?.recovery != nil else { return }
      draft.features[name] = .enabled
      downloadPreparation = name
    }
    if canSave {
      saveChoices(reviewRemoval: action == .turnOffAndRemoveAll)
    } else if action == .turnOffAndRemoveAll {
      reviewCleanup()
    }
  }

  var policyStateTitle: String {
    if policyError != nil { return "Settings unavailable" }
    if !loaded { return "Loading settings…" }
    if readOnly { return "Managed by Nix" }
    if !policyExists { return "Not set up yet" }
    return hasChanges ? "Unsaved changes" : "Saved choices"
  }

  var savedPolicyRequirement: String? {
    if policyError != nil { return "Open a valid settings file to continue." }
    if !loaded { return "Loading your settings…" }
    if busy { return "Wait for the current operation to finish." }
    if refreshing { return "Checking the current status…" }
    if !policyExists { return "Save your choices to continue." }
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
      return matchesSearch && featureFilter.includes(feature.id, draft: draft, saved: policy)
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
    guard canEditChoices else { return }
    draft.set(state, for: features.map(\.id))
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
      modelStatuses = [:]
      profileStatus = nil
      return
    }
    // Read an unsaved default policy without creating it on first launch
    let queryURL: URL? = policyExists || policyURL != Policy.defaultURL ? policyURL : nil
    do {
      let result = try await runner.run(.status, policyURL: queryURL)
      try result.requireSuccess()
      featureStatuses = try result.decode([String: FeatureStatus].self)
      statusError = nil
    } catch {
      featureStatuses = [:]
      statusError = String(describing: error)
    }
    activity = "Checking profile…"
    do {
      let result = try await runner.run(.profileStatus, policyURL: queryURL)
      // An absent profile exits 1 with valid JSON; query failures have no
      // status
      if result.standardOutput.isEmpty { try result.requireSuccess() }
      profileStatus = try result.decode(ProfileInstallationStatus.self)
      profileError = nil
    } catch {
      profileStatus = nil
      profileError = String(describing: error)
    }
    profileCheckedAt = Date()
    activity = "Checking models…"
    do {
      let result = try await runner.run(.models, policyURL: queryURL)
      if result.standardOutput.isEmpty { try result.requireSuccess() }
      modelStatuses = Dictionary(
        try result.decode([ModelStatus].self).map { ($0.assetSet, $0) },
        uniquingKeysWith: { first, _ in first })
      modelsError = nil
    } catch {
      modelStatuses = [:]
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
    guard exists == policyExists, current == policy else {
      throw CLIError(
        "This policy changed outside the app. Discard your pending edits and refresh before continuing."
      )
    }
  }

  func save() {
    saveChoices(reviewRemoval: false)
  }

  private func saveChoices(reviewRemoval: Bool) {
    guard canSave else { return }
    let names = policyExists ? changedNames : features.map(\.id)
    let requested = draft
    busy = true
    activity = "Saving settings…"
    notice = nil
    Task {
      var diagnostics: [String] = []
      var beganSaving = false
      var saved = false
      do {
        try verifyPolicyUnchanged()
        let groups = Dictionary(grouping: names, by: requested.state)
        for command in Command.allCases {
          guard let state = command.desiredState else { continue }
          guard let selected = groups[state], !selected.isEmpty else { continue }
          beganSaving = true
          let result = try await runner.run(command, names: selected, policyURL: policyURL)
          diagnostics.append(result.diagnostics)
          try result.requireSuccess()
        }
        profileNeedsReplacement = true
        notice = "Your choices have been saved."
        noticeDestination = .overview
        lastDiagnostics = diagnostics.joined(separator: "\n\n")
        await reload(replaceDraft: true)
        saved = loaded && !hasChanges
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
      if saved && reviewRemoval { reviewCleanup() }
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
    panel.title = "Open Settings File"
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
    modelStatuses = [:]
    profileStatus = nil
    profileCheckedAt = nil
    modelsCheckedAt = nil
    featureFilter = .all
    search = ""
    statusError = nil
    modelsError = nil
    profileError = nil
    profileNeedsReplacement = false
    downloadPreparation = nil
    quickActionReview = nil
    cleanupReview = nil
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
      title: "Opening profile installer…", command: .openProfile,
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
    performActivity(
      title: "Preparing removal preview…", failureTitle: "Removal preview unavailable"
    ) { [self] in
      try verifyPolicyUnchanged()
      let result = try await runner.run(
        .cleanup, policyURL: policyURL, cleanupReview: true)
      try result.requireSuccess()
      let plan = try result.decode(ModelCleanupPlan.self)
      guard (plan.targets + plan.skipped.map(\.name)).sorted() == cleanupTargets.sorted() else {
        throw CLIError("The removal preview changed. Refresh and review it again.")
      }
      cleanupReview = ModelCleanupOffer(plan: plan)
    }
  }

  func removeReviewedModels() {
    guard canUseSavedPolicy, let reviewed = cleanupReview?.targets, !reviewed.isEmpty else {
      return
    }
    cleanupReview = nil
    guard Set(reviewed).isSubset(of: Set(cleanupTargets)) else {
      issue = GUIIssue(
        title: "Removal preview changed", message: "Review the model selection again.")
      return
    }
    perform(
      title: "Requesting model removal…", command: .cleanup,
      success:
        "No model folders remain for the selected sets. Reclaimed disk space was not measured.",
      reviewedTargets: reviewed
    )
  }

  func download(_ name: String) {
    guard canUseSavedPolicy, policy.state(name) == .enabled,
      catalog?.features[name]?.recovery != nil
    else { return }
    perform(
      title: "Requesting download…", command: .download, names: [name],
      success:
        "Download requested for \(presentation(name).title). It continues in the background; refresh to check again."
    )
  }

  private func performActivity(
    title: String, failureTitle: String, refreshAfterward: Bool = false,
    operation: @escaping @MainActor () async throws -> Void
  ) {
    busy = true
    activity = title
    Task {
      defer { busy = false }
      do {
        try await operation()
      } catch {
        issue = GUIIssue(title: failureTitle, message: String(describing: error))
      }
      if refreshAfterward { await reload(replaceDraft: true) }
    }
  }

  private func perform(
    title: String, command: Command, names: [String] = [], success: String,
    reviewedTargets: [String]? = nil
  ) {
    notice = nil
    performActivity(
      title: title, failureTitle: "Operation could not be completed", refreshAfterward: true
    ) { [self] in
      try verifyPolicyUnchanged()
      let result: GUICommandResult
      if let reviewedTargets {
        result = try await runner.cleanup(
          reviewedTargets: reviewedTargets, policy: policy, policyURL: policyURL)
      } else {
        result = try await runner.run(command, names: names, policyURL: policyURL)
      }
      lastDiagnostics = result.diagnostics
      if command == .cleanup,
        result.terminationStatus == .exited(ExitStatus.verificationUnavailable.rawValue)
      {
        issue = GUIIssue(
          title: result.diagnostics.contains(ModelEliminationEvidence.confirmation)
            ? "Daemon reported elimination; folder verification unavailable"
            : "Removal requested; verification unavailable",
          message:
            "macOS accepted the request, but Pared could not inspect every selected model folder. Check the folder access guidance below, then refresh model status. You do not need to repeat removal just to check.\n\n\(result.diagnostics)"
        )
      } else if command == .cleanup,
        result.terminationStatus == .exited(ExitStatus.failure.rawValue),
        let reviewedTargets, let catalog
      {
        let assets = try catalog.modelAssets(reviewedTargets)
        let holders = try await modelHolders(assets)
        if !holders.isEmpty {
          lastDiagnostics +=
            "\nProcesses with selected model files open:\n"
            + holders.map {
              "\($0.name) (PID \($0.pid))"
                + ($0.canForceQuit ? "" : " — identity unavailable; cannot force quit")
            }.joined(separator: "\n")
            + "\nOpen files do not prove which process blocked removal."
        }
        modelQuitReview = ModelQuitOffer(assets: assets, holders: holders)
      } else {
        try result.requireSuccess()
        if command == .download, let name = names.first, downloadPreparation == name {
          downloadPreparation = nil
        }
        notice = success
        noticeDestination = command.isModelCommand ? .overview : .profile
      }
    }
  }

  func quitReviewedModelApps(force: Bool = false) {
    guard !working, let review = modelQuitReview else { return }
    modelQuitReview = nil
    performActivity(
      title: force ? "Force-quitting apps…" : "Asking apps to quit…",
      failureTitle: "Model cleanup could not be completed", refreshAfterward: true
    ) { [self] in
      try verifyPolicyUnchanged()
      guard Set(review.assets.map(\.name)).isSubset(of: Set(cleanupTargets)) else {
        throw CLIError("The eligible models changed. Review removal again.")
      }
      let messages: [String]
      let remaining: [ModelHolder]
      if force {
        let request = ModelHolderRequest(
          action: .force, assetSets: review.assets.map(\.name), reviewed: review.holders,
          policyURL: policyURL, policySnapshot: try JSONEncoder().encode(policy))
        let response =
          request.requiresAdministrator
          ? try await administratorModelHolders(request)
          : try await runModelHolderRequest(request)
        messages = response.messages
        remaining = response.holders
      } else {
        messages = try await quitModelHolders(review.holders, assets: review.assets)
        remaining = try await modelHolders(review.assets)
      }
      lastDiagnostics += "\n" + messages.joined(separator: "\n")
      if force && remaining.isEmpty {
        try verifyPolicyUnchanged()
        let targets = review.assets.map(\.name).sorted()
        guard Set(targets).isSubset(of: Set(cleanupTargets)) else {
          throw CLIError("The eligible models changed. Review removal again.")
        }
        let result = try await runner.cleanup(
          reviewedTargets: targets, policy: policy, policyURL: policyURL)
        lastDiagnostics += "\n" + result.diagnostics
        if result.terminationStatus == .exited(ExitStatus.verificationUnavailable.rawValue) {
          issue = GUIIssue(
            title: result.diagnostics.contains(ModelEliminationEvidence.confirmation)
              ? "Daemon reported elimination; folder verification unavailable"
              : "Removal requested; verification unavailable",
            message:
              "macOS accepted the retry, but Pared could not inspect every selected model folder. Check the folder access guidance below, then refresh model status.\n\n\(result.diagnostics)"
          )
        } else {
          try result.requireSuccess()
          notice =
            "Holder recheck finished and removal was retried. No selected model folders remain."
        }
      } else if force {
        modelQuitReview = ModelQuitOffer(assets: review.assets, holders: remaining)
        notice =
          "Model users remain or restarted. Review the current holders before another attempt."
      } else {
        notice = "Quit requests finished. Model status was refreshed; removal was not repeated."
      }
      noticeDestination = .models
    }
  }

  func inspectModelHoldersAsAdministrator() {
    guard !working, let review = modelQuitReview else { return }
    busy = true
    activity = "Inspecting model users with administrator access…"
    Task {
      do {
        try verifyPolicyUnchanged()
        let response = try await administratorModelHolders(
          ModelHolderRequest(action: .inspect, assetSets: review.assets.map(\.name), reviewed: []))
        modelQuitReview = ModelQuitOffer(assets: review.assets, holders: response.holders)
      } catch {
        modelQuitReview = nil
        issue = GUIIssue(
          title: "Model users could not be inspected", message: String(describing: error))
      }
      busy = false
    }
  }
}
