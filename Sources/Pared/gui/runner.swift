import Foundation
import Subprocess

typealias GUICommandResult = ExecutionResult<Void, DataOutput, StringOutput<UTF8>>

extension ExecutionResult
where
  ClosureResult == Void, Output == DataOutput,
  Error == StringOutput<UTF8>
{
  var diagnostics: String { standardError.trimmingCharacters(in: .whitespacesAndNewlines) }

  func requireSuccess() throws {
    guard terminationStatus.isSuccess else {
      throw CLIError(
        diagnostics.isEmpty ? "The operation failed: \(terminationStatus)" : diagnostics)
    }
  }

  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: standardOutput)
  }
}

// Run the CLI in a child process so its XPC waits cannot freeze the interface
// Subprocess drains stdout and stderr concurrently while awaiting termination
actor GUICommandRunner {
  private let executable: URL

  init(executable: URL) {
    self.executable = executable
  }

  func cleanup(reviewedTargets: [String], policy: Policy, policyURL: URL) async throws
    -> GUICommandResult
  {
    let current = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: policyURL))
    guard current == policy else {
      throw CLIError("The policy changed. Refresh and review model removal again.")
    }
    guard !reviewedTargets.isEmpty else {
      throw CLIError("No model sets were reviewed; no request sent")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-review-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshotURL = directory.appendingPathComponent("policy.json")
    try jsonData(policy).write(to: snapshotURL, options: .atomic)
    // The CLI validates the explicit selection against this reviewed snapshot
    // A concurrent policy edit cannot broaden removal to other eligible sets
    return try await run(.cleanup, policyURL: snapshotURL, reviewedAssetSets: reviewedTargets)
  }

  func run(
    _ command: Command, names: [String] = [], policyURL: URL?, dryRun: Bool = false,
    cleanupReview: Bool = false, reviewedAssetSets: [String] = []
  ) async throws -> GUICommandResult {
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
    let result = try await Subprocess.run(
      .path(.init(executable.path)),
      arguments: Arguments(
        command.arguments + names + (dryRun ? ["--dry-run"] : [])
          + (cleanupReview ? ["--review"] : [])
          + reviewedAssetSets.flatMap { ["--asset-set", $0] }
          + (explicitPolicy.map { ["--policy", $0.path] } ?? [])),
      output: .data(limit: .max), error: .string(limit: .max))
    if case .signaled(let signal) = result.terminationStatus {
      throw CLIError(
        "The operation terminated with signal \(signal)"
          + (result.diagnostics.isEmpty ? "" : ": \(result.diagnostics)"))
    }
    return result
  }
}

extension ModelStatus {
  var summary: String {
    if queryError == nil, localSnapshot?.vendingAtomicInstanceForConfiguredEntries == true {
      return "Available to apps"
    }
    if payloadDirectories?.isEmpty == false { return "Local assets reported" }
    if inventoryError != nil { return "Folder inventory unavailable" }
    if queryError != nil { return "Status unavailable" }
    if payloadDirectories?.isEmpty == true { return "No local assets reported" }
    guard let snapshot = localSnapshot else { return "Status unknown" }
    if snapshot.downloadedFilesystemBytes > 0 {
      return "Local assets reported"
    }
    return "No local assets reported"
  }
}
