import Foundation

struct GUICommandResult: Sendable {
  let output: Data
  let diagnostics: String
  let exitCode: Int32

  func requireSuccess() throws {
    guard exitCode == 0 else {
      throw CLIError(
        diagnostics.isEmpty ? "The operation exited with code \(exitCode)" : diagnostics)
    }
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: output)
  }
}

// Run the existing CLI away from the main actor so its XPC waits cannot freeze
// the interface. Each child process gets private output files to avoid pipe
// buffer deadlocks while retaining diagnostics from partial failures
actor GUICommandRunner {
  private let executable: URL

  init(executable: URL) {
    self.executable = executable
  }

  func cleanup(reviewedTargets: [String], policyData: Data, policyURL: URL) throws
    -> GUICommandResult
  {
    let current = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: policyURL))
    guard try jsonData(current) == policyData else {
      throw CLIError("The policy changed. Refresh and review model removal again.")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-review-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshotURL = directory.appendingPathComponent("policy.json")
    try policyData.write(to: snapshotURL, options: .atomic)
    // Use the reviewed snapshot for both commands so a concurrent CLI edit
    // cannot broaden the selection between preview and removal
    let preview = try run(["models", "cleanup", "--dry-run"], policyURL: snapshotURL)
    try preview.requireSuccess()
    guard try preview.decode([String].self) == reviewedTargets else {
      throw CLIError("The removal preview changed. Review the model selection again.")
    }
    return try run(["models", "cleanup"], policyURL: snapshotURL)
  }

  func run(_ arguments: [String], policyURL: URL?) throws -> GUICommandResult {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("output")
    let errorURL = directory.appendingPathComponent("diagnostics")
    for url in [outputURL, errorURL] {
      guard
        FileManager.default.createFile(
          atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw CLIError("Cannot create a private command output file") }
    }
    let output = try FileHandle(forWritingTo: outputURL)
    defer { try? output.close() }
    let diagnostics = try FileHandle(forWritingTo: errorURL)
    defer { try? diagnostics.close() }
    let process = Process()
    process.executableURL = executable
    // The CLI requires an existing file for --policy. The implicit default
    // path also supports creating the first policy when saving feature choices
    let explicitPolicy = policyURL.flatMap { url -> URL? in
      if url.standardizedFileURL == Policy.defaultURL.standardizedFileURL,
        !FileManager.default.fileExists(atPath: url.path)
      {
        return nil
      }
      return url
    }
    process.arguments = arguments + (explicitPolicy.map { ["--policy", $0.path] } ?? [])
    process.standardOutput = output
    process.standardError = diagnostics
    process.standardInput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return GUICommandResult(
      output: try Data(contentsOf: outputURL),
      diagnostics: String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      exitCode: process.terminationStatus)
  }
}

struct GUIFeatureStatus: Decodable {
  struct ObservedPreference: Decodable {
    let domain: String
    let key: String
    let value: Bool?
    let forced: Bool
  }

  let desired: FeatureState
  let preferences: [ObservedPreference]
  let managementRequired: Bool
  let modelAvailabilityOnly: Bool
}

struct GUIProfileStatus: Decodable {
  let installed: Bool
  let installedPayloadCount: Int
  let conflictingProfileIdentifiers: [String]
}

struct GUIModelStatus: Decodable {
  struct Snapshot: Decodable {
    let downloadedFilesystemBytes: Int64
    let configuredAssetEntries: Int
    let vendingAtomicInstanceForConfiguredEntries: Bool
  }

  let assetSet: String
  let queryError: String?
  let inventoryError: String?
  let localSnapshot: Snapshot?
  let payloadDirectories: [String]?

  var summary: String {
    if queryError != nil { return "Status unavailable" }
    guard let snapshot = localSnapshot else { return "Status unknown" }
    if snapshot.vendingAtomicInstanceForConfiguredEntries { return "Available to apps" }
    if (payloadDirectories?.isEmpty == false) || snapshot.downloadedFilesystemBytes > 0 {
      return "Local assets reported"
    }
    return "No local assets reported"
  }
}
