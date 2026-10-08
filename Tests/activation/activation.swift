// Exercise the generated activation shell with a fake cleanup executable
import Foundation

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

private struct CheckFailure: LocalizedError {
  let errorDescription: String?
}

private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw CheckFailure(errorDescription: message) }
}

private final class ActivationTests {
  private let root: URL
  private var policy: URL { root.appendingPathComponent("policy.json") }
  private var marker: URL {
    root.appendingPathComponent("state with spaces/cleaned-policy.json")
  }

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("pared-activation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{\"defaultState\":\"disabled\"}\n".utf8).write(to: policy)
  }

  deinit { try? FileManager.default.removeItem(at: root) }

  @discardableResult
  private func activate(code: Int = 0) throws -> String {
    let stdout = root.appendingPathComponent("stdout")
    let stderr = root.appendingPathComponent("stderr")
    try Data().write(to: stdout)
    try Data().write(to: stderr)
    let outputHandle = try FileHandle(forWritingTo: stdout)
    let errorHandle = try FileHandle(forWritingTo: stderr)
    defer {
      try? outputHandle.close()
      try? errorHandle.close()
      try? FileManager.default.removeItem(at: stdout)
      try? FileManager.default.removeItem(at: stderr)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    process.currentDirectoryURL = root
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["PARED_TEST_EXIT": String(code)], uniquingKeysWith: { _, new in new })
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + 15) == .timedOut {
      kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
      throw CheckFailure(errorDescription: "Activation timed out")
    }
    process.waitUntilExit()
    let output = try String(contentsOf: stdout, encoding: .utf8)
    let errors = try String(contentsOf: stderr, encoding: .utf8)
    try expect(
      process.terminationReason == .exit && process.terminationStatus == 0, output + errors)
    try expect(!errors.contains("No such file"), errors)
    return errors
  }

  private func calls() throws -> [Substring] {
    try String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8)
      .split(separator: "\n")
  }

  private func changePolicy() throws {
    try Data("{\"defaultState\":\"enabled\"}\n".utf8).write(to: policy)
  }

  func testSuccessSkipsUnchangedAndRetriesChangedPolicy() throws {
    try activate()
    try expect(
      Data(contentsOf: marker) == Data(contentsOf: policy), "Success marker differs from policy")
    let attributes = try FileManager.default.attributesOfItem(
      atPath: marker.deletingLastPathComponent().path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
      throw CheckFailure(errorDescription: "Missing state directory permissions")
    }
    let mode = permissions.intValue
    try expect(mode & 0o777 == 0o700, "State directory permissions are not 0700")
    try activate()
    try expect(
      calls() == ["models cleanup --policy policy.json"], "Unchanged policy triggered cleanup")
    try changePolicy()
    try activate()
    try expect(calls().count == 2, "Changed policy did not trigger cleanup")
    try expect(
      Data(contentsOf: marker) == Data(contentsOf: policy),
      "Changed policy was not marked successful")
    try expect(
      !FileManager.default.fileExists(atPath: marker.path + ".tmp"), "Temporary marker remains")
  }

  func testFailuresRetryWithoutMarkingSuccess() throws {
    for code in [1, 2, 69] {
      let errors = try activate(code: code)
      try expect(
        errors.contains("the next activation will retry"), "Failure did not report retry: \(code)")
      try expect(
        !FileManager.default.fileExists(atPath: marker.path),
        "Failure created a success marker: \(code)")
    }
    try activate()
    try expect(calls().count == 4, "Failed cleanup was not retried")
    try expect(
      Data(contentsOf: marker) == Data(contentsOf: policy), "Retry did not save the success marker")
  }

  func testFailedPolicyChangePreservesPreviousMarker() throws {
    try activate()
    let previous = try Data(contentsOf: marker)
    try changePolicy()
    try activate(code: 1)
    try expect(Data(contentsOf: marker) == previous, "Failed cleanup overwrote the previous marker")
    try activate()
    try expect(calls().count == 3, "Changed policy was not retried")
    try expect(
      Data(contentsOf: marker) == Data(contentsOf: policy),
      "Successful retry did not update the marker")
  }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(
    Data("Usage: swift Tests/activation/activation.swift ACTIVATION_SCRIPT\n".utf8))
  exit(1)
}
private let checks: [(String, (ActivationTests) throws -> Void)] = [
  (
    "Success skips unchanged and retries changed policy",
    { try $0.testSuccessSkipsUnchangedAndRetriesChangedPolicy() }
  ),
  ("Failures retry without marking success", { try $0.testFailuresRetryWithoutMarkingSuccess() }),
  (
    "Failed policy changes preserve the previous marker",
    { try $0.testFailedPolicyChangePreservesPreviousMarker() }
  ),
]
var failures = 0
for (name, check) in checks {
  do {
    try check(ActivationTests())
    print("PASS: \(name)")
  } catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: \(name): \(error.localizedDescription)\n".utf8))
  }
}
print("Activation: \(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
