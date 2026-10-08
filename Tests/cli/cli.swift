// Regression tests against the built CLI; no preferences or assets are changed
import Foundation

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

private struct Catalog: Decodable {
  struct Feature: Decodable {
    let assetSets: [String]
  }
  let features: [String: Feature]
  let assetTypes: [String: String]
  let recoveryAssetTypes: [String: String]?
}

private struct CheckFailure: LocalizedError {
  let errorDescription: String?
}

private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(errorDescription: message) }
}

private final class ModelPolicyTests {
  private let directory: URL
  private var policy: URL { directory.appendingPathComponent("policy.json") }

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private func runCLI(_ arguments: [String], code: Int32 = 0) throws -> Data {
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-output-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    let output = outputDirectory.appendingPathComponent("stdout")
    let errors = outputDirectory.appendingPathComponent("stderr")
    try Data().write(to: output)
    try Data().write(to: errors)
    let handle = try FileHandle(forWritingTo: output)
    let errorHandle = try FileHandle(forWritingTo: errors)
    defer {
      try? handle.close()
      try? errorHandle.close()
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    process.arguments = arguments + ["--policy", policy.path]
    process.standardOutput = handle
    process.standardError = errorHandle
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + 15) == .timedOut {
      kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
      throw CheckFailure(errorDescription: "CLI timed out: \(arguments)")
    }
    process.waitUntilExit()
    let data = try Data(contentsOf: output)
    let errorData = try Data(contentsOf: errors)
    try expect(process.terminationReason == .exit, "CLI terminated by signal: \(arguments)")
    try expect(
      process.terminationStatus == code,
      "\(arguments): expected exit \(code), got \(process.terminationStatus)\n\(String(decoding: data + errorData, as: UTF8.self))"
    )
    return data
  }

  private func writePolicy(_ features: [String: String]) throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1, "defaultState": "disabled", "features": features,
    ])
    try data.write(to: policy)
  }

  private func catalog() throws -> Catalog {
    try JSONDecoder().decode(
      Catalog.self,
      from: Data(contentsOf: URL(fileURLWithPath: "Sources/Pared/Resources/catalog.json")))
  }

  private func cleanupTargets() throws -> Set<String> {
    Set(try JSONDecoder().decode([String].self, from: runCLI(["models", "cleanup", "--dry-run"])))
  }

  func testEveryRetainedConsumerProtectsItsModels() throws {
    for (name, feature) in try catalog().features {
      for state in ["enabled", "unmanaged"] {
        try writePolicy([name: state])
        try expect(
          cleanupTargets().isDisjoint(with: feature.assetSets),
          "\(name): \(state) models were cleanup targets")
      }
    }
  }

  func testImageFeaturesRetainLanguageModels() throws {
    for name in ["genmoji", "imagePlayground"] {
      try writePolicy([name: "enabled"])
      try expect(
        !cleanupTargets().contains("com.apple.modelcatalog"),
        "\(name) did not retain language models")
    }
  }

  func testDownloadDependenciesCannotBeCleaned() throws {
    try writePolicy([:])
    let targets = try cleanupTargets()
    let catalog = try catalog()
    try expect(
      targets == Set(catalog.assetTypes.keys), "Cleanup targets differ from the catalog asset types"
    )
    try expect(
      targets.isDisjoint(with: catalog.recoveryAssetTypes?.keys.map { $0 } ?? []),
      "Cleanup includes recovery assets")
    try expect(
      !targets.contains("com.apple.MobileAsset.UAF.FM.Overrides"), "Cleanup includes FM overrides")
    try expect(
      !targets.contains("com.apple.MobileAsset.UAF.Shortcuts.Generator"),
      "Cleanup includes the Shortcuts generator")
  }

  func testRejectedRequestsAndDryRunsDoNotWrite() throws {
    try writePolicy(["photosCleanup": "enabled"])
    let before = try Data(contentsOf: policy)
    struct Request: Decodable { let name: String }
    let request = try JSONDecoder().decode(
      [Request].self,
      from: runCLI(["models", "download", "photosCleanup", "photosCleanup", "--dry-run"]))
    try expect(request.count == 1, "Duplicate download requests were not deduplicated")
    try expect(request.first?.name == "photosCleanup", "Unexpected download request")
    for arguments in [
      ["models", "download", "spatialPhotos"],
      ["models", "download"],
      ["models", "status", "--dry-run"],
      ["enable", "unknown", "--dry-run"],
      ["models"],
    ] {
      _ = try runCLI(arguments, code: 1)
    }
    try expect(
      Data(contentsOf: policy) == before, "Rejected requests or dry runs changed the policy")
    try expect(
      FileManager.default.contentsOfDirectory(atPath: directory.path) == ["policy.json"],
      "CLI wrote extra files")
  }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: swift Tests/cli/cli.swift PARED_BINARY\n".utf8))
  exit(1)
}
private let checks: [(String, (ModelPolicyTests) throws -> Void)] = [
  (
    "Retained consumers protect their models",
    { try $0.testEveryRetainedConsumerProtectsItsModels() }
  ),
  ("Image features retain language models", { try $0.testImageFeaturesRetainLanguageModels() }),
  ("Download dependencies cannot be cleaned", { try $0.testDownloadDependenciesCannotBeCleaned() }),
  (
    "Rejected requests and dry runs do not write",
    { try $0.testRejectedRequestsAndDryRunsDoNotWrite() }
  ),
]
var failures = 0
for (name, check) in checks {
  do {
    try check(ModelPolicyTests())
    print("PASS: \(name)")
  } catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: \(name): \(error.localizedDescription)\n".utf8))
  }
}
print("CLI: \(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
