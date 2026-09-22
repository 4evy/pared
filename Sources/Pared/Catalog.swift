import Foundation

struct Preference: Decodable {
  let domain: String
  let key: String
  let inverted: Bool
}

enum ModelUsage: String, Codable {
  case enabled = "ENABLED"
}

struct DeclarationPath: Decodable {
  let group: DeclarationGroup
  let components: [String]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let path = try container.decode(String.self)
    let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count > 1, let group = DeclarationGroup(rawValue: parts[0]),
      parts.allSatisfy({ !$0.isEmpty })
    else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid declaration path: \(path)")
    }
    self.group = group
    components = Array(parts.dropFirst())
  }
}

struct ModelRecovery: Codable {
  let subscriber: String
  let name: String
  let usageAliases: [String: String]
  let assetSetUsages: [String: [String: ModelUsage]]?
  let additionalAssetSets: [String]?
  let minimumOSMajorVersion: Int?
}

struct Feature: Decodable {
  let description: String
  let preferences: [Preference]
  let restrictions: [String]
  let declarations: [DeclarationPath]
  let assetSets: [String]
  let recovery: ModelRecovery?
}

struct DownloadBlocking: Decodable {
  let domain: String
  let keyPrefix: String
  let url: String
}

struct Catalog: Decodable {
  static let supportedSchemaVersion = 1
  let schemaVersion: Int
  let features: [String: Feature]
  let assetTypes: [String: String]
  // Download-only dependencies must never become cleanup targets
  let recoveryAssetTypes: [String: String]?
  let preferenceUUIDs: [String: String]
  let downloadBlocking: DownloadBlocking

  var downloadAssetTypes: [String: String] {
    assetTypes.merging(recoveryAssetTypes ?? [:]) { existing, _ in existing }
  }

  static func load() throws -> Catalog {
    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
      throw CLIError("Feature catalog is missing")
    }
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    guard catalog.schemaVersion == supportedSchemaVersion else {
      throw CLIError("Unsupported catalog schema version: \(catalog.schemaVersion)")
    }
    guard Set(catalog.assetTypes.keys).isDisjoint(with: (catalog.recoveryAssetTypes ?? [:]).keys)
    else { throw CLIError("Cleanup and download-only asset types must be disjoint") }
    guard catalog.preferenceUUIDs[catalog.downloadBlocking.domain] != nil else {
      throw CLIError("Missing download blocking profile identity")
    }
    for (name, feature) in catalog.features {
      guard feature.assetSets.allSatisfy({ catalog.assetTypes[$0] != nil }),
        feature.preferences.allSatisfy({ catalog.preferenceUUIDs[$0.domain] != nil })
      else { throw CLIError("Incomplete catalog mappings for \(name)") }
      if let recovery = feature.recovery {
        let allowed = Set(feature.assetSets + (recovery.additionalAssetSets ?? []))
        guard !recovery.name.isEmpty, !recovery.subscriber.isEmpty,
          !recovery.usageAliases.isEmpty || !(recovery.assetSetUsages ?? [:]).isEmpty,
          allowed.allSatisfy({ catalog.downloadAssetTypes[$0] != nil }),
          Set((recovery.assetSetUsages ?? [:]).keys).isSubset(of: allowed)
        else { throw CLIError("Incomplete recovery mappings for \(name)") }
      }
    }
    return catalog
  }
}

struct CLIError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

func report(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}
