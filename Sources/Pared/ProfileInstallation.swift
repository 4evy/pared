import AppKit
import Foundation

func openProfileInstallation(policy: Policy, catalog: Catalog) throws {
  // Stage outside the input policy directory: --policy may point into /nix/store
  // Keep the file available while System Settings reviews it asynchronously
  let directory = Policy.defaultURL.deletingLastPathComponent()
    .appendingPathComponent("installation", isDirectory: true)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
  let url = directory.appendingPathComponent(Artifacts.profileFilename)
  try profileData(policy: policy, catalog: catalog).write(to: url, options: .atomic)
  guard NSWorkspace.shared.open(url) else {
    throw CLIError(
      "Could not open the profile installer. Open this file in System Settings: \(url.path)")
  }
  report("Opened profile installation: \(url.path)")
  report(
    "Complete review and installation in System Settings. Opening the file does not install it.")
  report("Then run pared profile status to check whether the device profile is installed.")
}
