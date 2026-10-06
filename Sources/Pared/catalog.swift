import Foundation

struct Preference: Decodable, Identifiable {
  struct ID: Hashable {
    let domain: String
    let key: String
  }

  let domain: String
  let key: String
  let inverted: Bool
  let title: String?

  var id: ID { ID(domain: domain, key: key) }

  func value(for state: FeatureState) -> Bool { (state == .enabled) != inverted }
}

enum FeatureGroup: String, CaseIterable, Decodable {
  case siriAndWriting = "Siri & Writing"
  case apps = "Apps"
  case system = "System"
  case sharedModels = "Shared Models"
}

struct FeatureDisplay: Decodable {
  let title: String
  let symbol: String
  let group: FeatureGroup
  let wizardTitle: String?
  let downloadPurpose: String?
  let note: String?
}

struct ModelDisplay: Decodable {
  let title: String
  let wizardTitle: String
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
  let display: FeatureDisplay?
  let preferences: [Preference]
  let restrictions: [String]
  let declarations: [DeclarationPath]
  let assetSets: [String]
  let recovery: ModelRecovery?

  var managementRequired: Bool {
    !restrictions.isEmpty || !declarations.isEmpty || !assetSets.isEmpty
  }

  var modelAvailabilityOnly: Bool {
    preferences.isEmpty && restrictions.isEmpty && declarations.isEmpty
  }

  var controls: [String] {
    [
      ("preferences", !preferences.isEmpty),
      ("profile", !restrictions.isEmpty || !assetSets.isEmpty),
      ("MDM", !declarations.isEmpty),
      ("models", !assetSets.isEmpty),
    ].compactMap { label, present in present ? label : nil }
  }

  var downloadAssetSets: [String] { assetSets + (recovery?.additionalAssetSets ?? []) }
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
  let modelDisplay: [String: ModelDisplay]?
  // These dependencies may be downloaded but are excluded from cleanup
  let recoveryAssetTypes: [String: String]?
  let preferenceUUIDs: [String: String]
  let downloadBlocking: DownloadBlocking

  var downloadAssetTypes: [String: String] {
    assetTypes.merging(recoveryAssetTypes ?? [:]) { existing, _ in existing }
  }

  var featureNames: [String] { features.keys.sorted() }

  var presentations: [FeaturePresentation] { featureNames.map(presentation) }

  func modelAssets(_ names: [String], includingDownloadDependencies: Bool = false)
    throws(CLIError) -> [ModelAssetSet]
  {
    let types = includingDownloadDependencies ? downloadAssetTypes : assetTypes
    return try names.map { name throws(CLIError) -> ModelAssetSet in
      guard let assetType = types[name] else {
        throw CLIError("Missing asset type in the catalog for \(name); no request sent")
      }
      return ModelAssetSet(name: name, assetType: assetType)
    }
  }

  func selectedFeatureNames(_ requested: [String]) throws(CLIError) -> [String] {
    if requested.contains("all") {
      guard requested == ["all"] else { throw CLIError("Use 'all' alone") }
      return featureNames
    }
    for name in requested where features[name] == nil {
      throw CLIError("Unknown feature: \(name)")
    }
    return Set(requested).sorted()
  }

  func assetSets(
    for names: some Sequence<String>, at keyPath: KeyPath<Feature, [String]> = \.assetSets
  ) -> [String] {
    Set(names.flatMap { features[$0]![keyPath: keyPath] }).sorted()
  }

  func consumers(of assetSet: String) -> [String] {
    features.filter { $0.value.assetSets.contains(assetSet) }.keys.sorted()
  }

  func presentation(_ name: String) -> FeaturePresentation {
    FeaturePresentation(name, feature: features[name])
  }

  func modelTitle(_ assetSet: String, wizard: Bool = false) -> String {
    guard let display = modelDisplay?[assetSet] else { return assetSet }
    return wizard ? display.wizardTitle : display.title
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
      guard Set(feature.preferences.map(\.id)).count == feature.preferences.count else {
        throw CLIError("Duplicate preference mappings for \(name)")
      }
      guard feature.assetSets.allSatisfy({ catalog.assetTypes[$0] != nil }),
        feature.preferences.allSatisfy({ catalog.preferenceUUIDs[$0.domain] != nil })
      else { throw CLIError("Incomplete catalog mappings for \(name)") }
      if let recovery = feature.recovery {
        let allowed = Set(feature.downloadAssetSets)
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

struct FeaturePresentation: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let group: FeatureGroup
  let wizardTitle: String
  let downloadPurpose: String

  init(_ name: String, feature: Feature? = nil) {
    id = name
    title = feature?.display?.title ?? feature?.description ?? name
    symbol = feature?.display?.symbol ?? "slider.horizontal.3"
    group = feature?.display?.group ?? .system
    wizardTitle = feature?.display?.wizardTitle ?? feature?.description ?? name
    downloadPurpose = feature?.display?.downloadPurpose ?? "Models used by this feature"
  }
}
