import AssetBridge
import Foundation

struct ModelCleanupPlan: Codable {
  struct Skipped: Codable {
    let name: String
    let reason: String
  }

  let targets: [String]
  let skipped: [Skipped]

  // Review mappings without cancelling subscriptions or requesting removal
  static func prepare(_ targets: [String], catalog: Catalog) throws -> Self {
    guard targets.isEmpty || paredAssetRuntimeIsAvailable() else {
      throw CLIError("Cannot load UnifiedAssetFramework; no request sent")
    }
    var supported: [String] = []
    var skipped: [Skipped] = []
    for name in targets {
      do {
        let assets = try catalog.modelAssets([name])
        for asset in assets { try asset.validateConfiguration() }
        supported.append(name)
      } catch {
        skipped.append(Skipped(name: name, reason: String(describing: error)))
      }
    }
    return Self(targets: supported, skipped: skipped)
  }
}
