import AssetBridge
import Foundation
import Subprocess

enum ModelHolderAction: String, Codable, Sendable {
  case inspect
  case force
}

struct ModelHolderRequest: Codable, Sendable {
  let action: ModelHolderAction
  let assetSets: [String]
  let reviewed: [ModelHolder]
  var policyURL: URL? = nil
  var policySnapshot: Data? = nil

  var requiresAdministrator: Bool {
    reviewed.contains { $0.canForceQuit && $0.userID != getuid() }
  }
}

struct ModelHolderResponse: Codable, Sendable {
  let holders: [ModelHolder]
  let messages: [String]
}

func runModelHolderRequest(_ request: ModelHolderRequest) async throws -> ModelHolderResponse {
  guard paredAssetRuntimeIsAvailable() else {
    throw CLIError("Cannot load UnifiedAssetFramework for model-holder inspection")
  }
  let catalog = try Catalog.load()
  guard !request.assetSets.isEmpty, request.assetSets.count <= catalog.assetTypes.count,
    Set(request.assetSets).count == request.assetSets.count, request.reviewed.count <= 128
  else { throw CLIError("Invalid model-holder selection") }
  let assets = try catalog.modelAssets(request.assetSets)
  for asset in assets { try asset.validateConfiguration() }
  let verifySelection: @Sendable () throws -> Void = {
    guard let url = request.policyURL, let snapshot = request.policySnapshot else {
      throw CLIError("Force quit requires the reviewed policy")
    }
    let expected = try JSONDecoder().decode(Policy.self, from: snapshot)
    let currentCatalog = try Catalog.load()
    try expected.validate(currentCatalog)
    let current = try Policy.load(url, explicit: true, catalog: currentCatalog)
    guard expected == current,
      Set(request.assetSets).isSubset(of: Set(current.cleanupTargets(currentCatalog)))
    else { throw CLIError("The policy changed. Review model removal again.") }
  }
  if request.action == .force {
    guard request.reviewed.contains(where: \.canForceQuit) else {
      throw CLIError("Force quit requires an identified, reviewed model user")
    }
    try verifySelection()
  }
  let messages =
    request.action == .force
    ? try await forceModelHolders(
      request.reviewed, assets: assets, verifySelection: verifySelection) : []
  return ModelHolderResponse(holders: try await modelHolders(assets), messages: messages)
}

// Send a bounded review in an argument, with no privileged temporary files or
// password handling. macOS owns the administrator authentication dialog
func administratorModelHolders(_ request: ModelHolderRequest) async throws -> ModelHolderResponse {
  let encoded = try JSONEncoder().encode(request).base64EncodedString()
  guard encoded.count <= 64 * 1024, let executable = Bundle.main.executableURL else {
    throw CLIError("The administrator model-holder request is unavailable")
  }
  let prompt =
    request.action == .inspect
    ? "Pared needs administrator access to inspect users of the selected models."
    : "Pared needs administrator access to force quit the reviewed model users."
  // Pass values as arguments so AppleScript handles shell quoting
  let script = """
    on run argv
      set command to quoted form of (item 1 of argv) & " models holder-operation " & quoted form of (item 2 of argv)
      return do shell script command with administrator privileges with prompt (item 3 of argv)
    end run
    """
  let result = try await Subprocess.run(
    .path("/usr/bin/osascript"),
    arguments: Arguments(["-e", script, executable.path, encoded, prompt]),
    output: .data(limit: 1024 * 1024), error: .string(limit: 64 * 1024))
  guard result.terminationStatus.isSuccess else {
    throw CLIError(
      "Administrator inspection or force quit did not complete: \(result.diagnostics)")
  }
  return try result.decode(ModelHolderResponse.self)
}
