import Foundation

/// Installs the running release without changing policy or feature settings
enum WizardInstallation {
  private static let executableName = "pared"
  private static let bundleName = "pared_Pared.bundle"
  private static let markerName = ".pared-installer"
  private static let ownedNames: Set<String> = [executableName, bundleName, markerName]

  static func install(prefix: URL) throws -> URL {
    let files = FileManager.default
    let prefix = prefix.standardizedFileURL
    let binDirectory = prefix.appendingPathComponent("bin", isDirectory: true)
    let libraryDirectory = prefix.appendingPathComponent("libexec", isDirectory: true)
    let destination = libraryDirectory.appendingPathComponent("pared", isDirectory: true)
    let command = binDirectory.appendingPathComponent(executableName)
    let installedExecutable = destination.appendingPathComponent(executableName)

    do {
      try validateCommand(command, target: installedExecutable)
      try validateInstallation(destination)
      guard let runningExecutable = Bundle.main.executableURL else {
        throw CLIError("Could not locate the running Pared executable")
      }
      let sourceExecutable = runningExecutable.resolvingSymlinksInPath()
      let sourceBundle = Bundle.module.bundleURL.resolvingSymlinksInPath()
      guard try itemType(sourceExecutable) == .typeRegular,
        files.isExecutableFile(atPath: sourceExecutable.path)
      else {
        throw CLIError("The running executable is not a readable release: \(sourceExecutable.path)")
      }
      guard try itemType(sourceBundle) == .typeDirectory else {
        throw CLIError("The Pared resource bundle is missing: \(sourceBundle.path)")
      }
      if sourceExecutable == installedExecutable.resolvingSymlinksInPath(),
        try itemType(command) == .typeSymbolicLink
      {
        return command
      }

      try files.createDirectory(at: binDirectory, withIntermediateDirectories: true)
      try files.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
      let staging = libraryDirectory.appendingPathComponent(
        ".pared-install-\(UUID().uuidString)", isDirectory: true)
      try files.createDirectory(at: staging, withIntermediateDirectories: false)
      defer { try? files.removeItem(at: staging) }
      let payload = staging.appendingPathComponent("new", isDirectory: true)
      try files.createDirectory(at: payload, withIntermediateDirectories: false)
      try files.copyItem(at: sourceExecutable, to: payload.appendingPathComponent(executableName))
      try files.copyItem(at: sourceBundle, to: payload.appendingPathComponent(bundleName))
      try Data().write(to: payload.appendingPathComponent(markerName), options: .withoutOverwriting)
      try verifyPayload(payload)

      // Keep user-added files, including any policy stored beside the executable
      if try itemType(destination) != nil {
        for item in try files.contentsOfDirectory(
          at: destination, includingPropertiesForKeys: nil)
        where !ownedNames.contains(item.lastPathComponent) {
          try files.copyItem(at: item, to: payload.appendingPathComponent(item.lastPathComponent))
        }
      }

      // Recheck ownership after staging, before moving anything out of place
      try validateCommand(command, target: installedExecutable)
      try validateInstallation(destination)
      var backup: URL?
      var movedPayload = false
      do {
        if try itemType(destination) != nil {
          let backupDirectory = libraryDirectory.appendingPathComponent(
            ".pared-backup-\(UUID().uuidString)", isDirectory: true)
          try files.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
          let previous = backupDirectory.appendingPathComponent("previous", isDirectory: true)
          do {
            try files.moveItem(at: destination, to: previous)
          } catch {
            try? files.removeItem(at: backupDirectory)
            throw error
          }
          backup = previous
        }
        try files.moveItem(at: payload, to: destination)
        movedPayload = true
        if try itemType(command) == nil {
          try files.createSymbolicLink(
            atPath: command.path, withDestinationPath: installedExecutable.path)
        } else {
          try validateCommand(command, target: installedExecutable)
        }
      } catch {
        let installationError = error
        do {
          if movedPayload { try files.removeItem(at: destination) }
          if let backup {
            try files.moveItem(at: backup, to: destination)
            try? files.removeItem(at: backup.deletingLastPathComponent())
          }
        } catch {
          let recovery = backup.map { " Your previous installation is safe at \($0.path)." } ?? ""
          throw CLIError(
            "Installation failed: \(installationError). Automatic recovery also failed: \(error).\(recovery)"
          )
        }
        throw CLIError(
          "Installation failed; any previous installation was restored: \(installationError)")
      }
      if let backup {
        do {
          try files.removeItem(at: backup.deletingLastPathComponent())
        } catch {
          report(
            "Pared is installed, but its previous installation remains at \(backup.path): \(error)")
        }
      }
      return command
    } catch let error as CLIError {
      throw error
    } catch {
      throw CLIError(
        "Could not install Pared at \(prefix.path): \(error). Choose a directory writable by your user; do not use sudo."
      )
    }
  }

  static func shellProfile(environment: [String: String]) -> URL? {
    let home: URL
    if let path = environment["HOME"], !path.isEmpty, path.hasPrefix("/") {
      home = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      home = FileManager.default.homeDirectoryForCurrentUser
    }
    switch environment["SHELL"].map({ URL(fileURLWithPath: $0).lastPathComponent }) {
    case "zsh":
      let directory: URL
      if let path = environment["ZDOTDIR"], !path.isEmpty {
        directory = URL(fileURLWithPath: path, isDirectory: true, relativeTo: home).absoluteURL
      } else {
        directory = home
      }
      return directory.appendingPathComponent(".zshrc").standardizedFileURL
    case "bash": return home.appendingPathComponent(".bash_profile")
    case "sh", "dash", "ksh": return home.appendingPathComponent(".profile")
    default: return nil
    }
  }

  /// Appends only the installer's PATH line; the caller owns user confirmation
  static func addToPath(binDirectory: URL, profile: URL) throws {
    let files = FileManager.default
    let path = binDirectory.standardizedFileURL.path
    guard !path.contains("\n"), !path.contains("\r"), !path.contains("\0") else {
      throw CLIError("The PATH directory must not contain a newline, carriage return, or NUL")
    }
    let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    let line = "export PATH=\(quoted):$PATH"
    do {
      let target = try writableProfileTarget(profile)
      let type = try itemType(target)
      guard type == nil || type == .typeRegular else {
        throw CLIError("Shell configuration is not a regular file: \(profile.path)")
      }
      let existing = type == nil ? Data() : try Data(contentsOf: target)
      guard let text = String(data: existing, encoding: .utf8) else {
        throw CLIError("Shell configuration is not UTF-8; it was not changed: \(profile.path)")
      }
      if text.components(separatedBy: .newlines).contains(line) { return }
      if type == nil {
        try files.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target, options: .withoutOverwriting)
      }
      let handle = try FileHandle(forWritingTo: target)
      defer { try? handle.close() }
      try handle.seekToEnd()
      let separator = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
      try handle.write(contentsOf: Data((separator + "\n# pared installer\n" + line + "\n").utf8))
    } catch let error as CLIError {
      throw error
    } catch {
      throw CLIError("Could not append Pared's PATH line to \(profile.path): \(error)")
    }
  }

  private static func itemType(_ url: URL) throws -> FileAttributeType? {
    do {
      return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    } catch let error as NSError {
      if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
        return nil
      }
      throw error
    }
  }

  private static func validateCommand(_ command: URL, target: URL) throws {
    guard let type = try itemType(command) else { return }
    guard type == .typeSymbolicLink,
      try FileManager.default.destinationOfSymbolicLink(atPath: command.path) == target.path
    else {
      throw CLIError("Refusing to replace \(command.path): it belongs to another installation")
    }
  }

  private static func validateInstallation(_ destination: URL) throws {
    guard let type = try itemType(destination) else { return }
    guard type == .typeDirectory,
      try itemType(destination.appendingPathComponent(markerName)) == .typeRegular
    else {
      throw CLIError(
        "Refusing to replace \(destination.path): it is not managed by the Pared installer")
    }
  }

  private static func verifyPayload(_ payload: URL) throws {
    let bundleURL = payload.appendingPathComponent(bundleName, isDirectory: true)
    guard let bundle = Bundle(url: bundleURL),
      let catalog = bundle.url(forResource: "catalog", withExtension: "json"),
      FileManager.default.isReadableFile(atPath: catalog.path)
    else { throw CLIError("The staged release is missing its readable feature catalog") }
    let process = Process()
    process.executableURL = payload.appendingPathComponent(executableName)
    process.arguments = ["features"]
    process.currentDirectoryURL = payload
    process.standardOutput = FileHandle.nullDevice
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      let detail = String(decoding: diagnostics, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw CLIError(
        "The staged Pared release could not load its resources and run features (status \(process.terminationStatus))."
          + (detail.isEmpty ? "" : " \(detail)"))
    }
  }

  private static func writableProfileTarget(_ profile: URL) throws -> URL {
    var target = profile.standardizedFileURL
    for _ in 0..<40 {
      // Resolve parent links too, such as a chezmoi or Home Manager directory
      let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
      target = parent.appendingPathComponent(target.lastPathComponent)
      guard target.path != "/nix/store", !target.path.hasPrefix("/nix/store/") else {
        throw CLIError("Refusing to edit Nix-store-backed shell configuration: \(profile.path)")
      }
      if try itemType(target) != .typeSymbolicLink { return target }
      let link = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
      target = URL(fileURLWithPath: link, relativeTo: parent).absoluteURL.standardizedFileURL
    }
    throw CLIError("Shell configuration has too many symbolic links: \(profile.path)")
  }
}
