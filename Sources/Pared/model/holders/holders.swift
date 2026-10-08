import AppKit
import AssetBridge
import Foundation
import Subprocess

struct ModelHolder: Codable, Identifiable, Sendable {
  let pid: Int32
  let name: String
  let assetSets: [String]
  let applicationURL: URL?
  let launchedAt: Date?
  let processVersion: UInt32?
  let userID: UInt32?
  let executable: String?

  var id: Int32 { pid }
  var canQuit: Bool { applicationURL != nil && launchedAt != nil }
  var canForceQuit: Bool { processVersion != nil && userID != nil && executable != nil }
}

// Open files identify processes actually using selected payloads or lock files
// They do not prove which process blocked deletion, and missing entries do not
// prove that there are no daemon-managed locks
func modelHolders(_ assets: [ModelAssetSet]) async throws -> [ModelHolder] {
  guard !assets.isEmpty else { return [] }
  let versionsBeforeInspection = paredProcessVersions()
  let output = try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask {
      let result = try await Subprocess.run(
        .path("/usr/sbin/lsof"),
        arguments: ["-nP", "-F0pcufn"],
        output: .string(limit: 16 * 1024 * 1024), error: .string(limit: 64 * 1024))
      guard result.terminationStatus.isSuccess else {
        throw CLIError("Open model files could not be inspected: \(result.standardError)")
      }
      return result.standardOutput
    }
    group.addTask {
      try await Task.sleep(for: .seconds(10))
      throw CLIError("Inspecting open model files timed out; no apps were selected")
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
  let paths = assets.map { asset in
    (
      name: asset.name,
      payload: UnifiedAssets.assetDirectory.appendingPathComponent(
        asset.assetType.replacingOccurrences(of: ".", with: "_")
      ).path + "/",
      locks: UnifiedAssets.assetDirectory.appendingPathComponent(
        "locks/com.apple.UnifiedAssetFramework/\(asset.name)"
      ).path + "/"
    )
  }
  var pid: Int32?
  var processNames: [Int32: String] = [:]
  var processUsers: [Int32: UInt32] = [:]
  var matched: [Int32: Set<String>] = [:]
  var descriptor = ""
  for field in output.split(separator: "\0") {
    let field = field.drop(while: { $0 == "\n" })
    let value = String(field.dropFirst())
    switch field.first {
    case "p":
      pid = Int32(value)
      descriptor = ""
    case "c":
      if let pid { processNames[pid] = value }
    case "u":
      if let pid { processUsers[pid] = UInt32(value) }
    case "f": descriptor = value
    case "n":
      guard let pid, pid != getpid(), descriptor != "cwd", descriptor != "rtd" else { continue }
      for path in paths {
        if (value.hasPrefix(path.payload) && value.contains(".asset/"))
          || (value.hasPrefix(path.locks) && value.contains("/shared_locks/"))
        {
          matched[pid, default: []].insert(path.name)
        }
      }
    default: break
    }
  }
  return await MainActor.run {
    matched.map { pid, names in
      let app = NSRunningApplication(processIdentifier: pid)
      // Only foreground apps support normal quit; helpers use their own
      // process identity rather than a guessed parent application
      let identity = paredInspectProcess(pid, nil)
      let stable =
        identity.map { versionsBeforeInspection[NSNumber(value: pid)]?.uint32Value == $0.version }
        == true
      let canQuit =
        stable && processUsers[pid] == getuid()
        && app?.activationPolicy == .regular && app?.isTerminated == false
      return ModelHolder(
        pid: pid, name: app?.localizedName ?? processNames[pid] ?? "Process \(pid)",
        assetSets: names.sorted(), applicationURL: canQuit ? app?.bundleURL : nil,
        launchedAt: canQuit ? app?.launchDate : nil,
        processVersion: stable ? identity?.version : nil, userID: identity?.uid,
        executable: identity?.executable)
    }.sorted(
      using: KeyPathComparator(\.name, comparator: String.StandardComparator.localizedStandard))
  }
}

@MainActor
func quitModelHolders(
  _ reviewed: [ModelHolder], assets: [ModelAssetSet]
) async throws -> [String] {
  var messages: [String] = []
  for holder in reviewed where holder.canQuit {
    let current = try await modelHolders(assets)
    guard
      current.contains(where: {
        $0.pid == holder.pid && $0.applicationURL == holder.applicationURL
          && $0.launchedAt == holder.launchedAt
      }), let app = NSRunningApplication(processIdentifier: holder.pid),
      app.activationPolicy == .regular, app.bundleURL == holder.applicationURL,
      app.launchDate == holder.launchedAt, !app.isTerminated
    else {
      messages.append(
        "\(holder.name): no longer matches the reviewed model user; no quit request sent")
      continue
    }
    // Normal quit leaves save prompts and refusal to the app
    guard app.terminate() else {
      messages.append("\(holder.name): the quit request failed")
      continue
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !app.isTerminated && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(200))
    }
    messages.append(
      app.isTerminated
        ? "\(holder.name): quit"
        : "\(holder.name): still running; finish any save prompt or quit it manually"
    )
  }
  return messages
}

func forceModelHolders(
  _ reviewed: [ModelHolder], assets: [ModelAssetSet],
  verifySelection: @Sendable () throws -> Void
) async throws -> [String] {
  var messages: [String] = []
  for holder in reviewed where holder.canForceQuit {
    let current = try await modelHolders(assets)
    guard let version = holder.processVersion, let uid = holder.userID,
      let executable = holder.executable,
      current.contains(where: {
        $0.pid == holder.pid && $0.processVersion == version && $0.userID == uid
          && $0.executable == executable
      })
    else {
      messages.append("\(holder.name): no longer matches the reviewed holder; no signal sent")
      continue
    }
    var error: NSError?
    try verifySelection()
    guard paredForceQuitProcess(holder.pid, version, uid, executable, &error) else {
      messages.append(
        "\(holder.name): force quit failed: \(error?.localizedDescription ?? "unknown error")")
      continue
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while paredInspectProcess(holder.pid, nil)?.version == version && ContinuousClock.now < deadline
    {
      try await Task.sleep(for: .milliseconds(100))
    }
    var inspectionError: NSError?
    let after = paredInspectProcess(holder.pid, &inspectionError)
    if after?.version == version {
      messages.append("\(holder.name): still running after SIGKILL")
    } else if after != nil
      || (inspectionError?.domain == NSPOSIXErrorDomain && inspectionError?.code == Int(ESRCH))
    {
      messages.append("\(holder.name): reviewed process terminated")
    } else {
      messages.append("\(holder.name): no longer observable; termination is unverified")
    }
  }
  return messages
}
