import Darwin
// Run private API stress checks without changing asset subscriptions
// Use swift Tests/bridge/bridge.swift [--sanitize] [--repeat COUNT]
// Sanitizers cover bridge memory and reply races
import Foundation

private struct CheckFailure: LocalizedError {
  let errorDescription: String?
}

private func run(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  let finished = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in finished.signal() }
  try process.run()
  if finished.wait(timeout: .now() + 120) == .timedOut {
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    throw CheckFailure(errorDescription: "Command timed out: \(arguments.joined(separator: " "))")
  }
  process.waitUntilExit()
  guard process.terminationReason == .exit && process.terminationStatus == 0 else {
    throw CheckFailure(
      errorDescription:
        "Command failed (\(process.terminationStatus)): \(arguments.joined(separator: " "))")
  }
}

private func main() throws {
  var sanitize = false
  var repeatCount = 1
  var arguments = CommandLine.arguments.dropFirst().makeIterator()
  while let argument = arguments.next() {
    switch argument {
    case "--sanitize":
      sanitize = true
    case "--repeat":
      guard let value = arguments.next(), let count = Int(value), count > 0 else {
        throw CheckFailure(errorDescription: "--repeat must be a positive integer")
      }
      repeatCount = count
    case "--help", "-h":
      print("Usage: swift Tests/bridge/bridge.swift [--sanitize] [--repeat COUNT]")
      return
    default:
      throw CheckFailure(errorDescription: "Unknown argument: \(argument)")
    }
  }
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("pared-private-apis-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let native = root.appendingPathComponent("native").path
  let bridgeSources = try FileManager.default.contentsOfDirectory(atPath: "Sources/AssetBridge")
    .filter { $0.hasSuffix(".swift") }.sorted().map { "Sources/AssetBridge/\($0)" }
  try run(
    [
      "xcrun", "swiftc", "-swift-version", "6", "-warnings-as-errors", "-parse-as-library",
      "-O", "-g",
    ] + (sanitize ? ["-sanitize=address"] : []) + bridgeSources + [
      "Tests/bridge/native.swift", "-o", native,
    ])
  // Compile the private decoders together without exposing them to the product
  let reply = try String(contentsOfFile: "Sources/Pared/reply.swift", encoding: .utf8)
  let profile = try String(contentsOfFile: "Sources/Pared/profile/status.swift", encoding: .utf8)
  let harness = try String(contentsOfFile: "Tests/bridge/replies.swift", encoding: .utf8)
  let source = root.appendingPathComponent("replies.swift")
  try
    (reply.components(separatedBy: "extension Reply where Value == ExitStatus")[0]
    + profile.components(separatedBy: "func reportProfileInstallation()")[0]
    + harness).write(to: source, atomically: true, encoding: .utf8)
  let swiftFlags = sanitize ? ["-sanitize=thread"] : []
  let binary = root.appendingPathComponent("replies").path
  try run(
    [
      "xcrun", "swiftc", "-swift-version", "6", "-warnings-as-errors", "-parse-as-library", "-O",
      "-g",
    ] + swiftFlags + [source.path, "-o", binary])
  for _ in 0..<repeatCount {
    try run([native, "Sources/Pared/Resources/catalog.json"])
    try run([binary])
  }
}

do {
  try main()
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
