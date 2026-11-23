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
  let darwinNotification: String?

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
    let parts = path.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count > 1, let group = DeclarationGroup(rawValue: String(parts[0])),
      parts.allSatisfy({ !$0.isEmpty })
    else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid declaration path: \(path)")
    }
    self.group = group
    components = parts.dropFirst().map(String.init)
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

  var modelAvailabilityOnly: Bool {
    preferences.isEmpty && restrictions.isEmpty && declarations.isEmpty
  }

  var downloadAssetSets: [String] { assetSets + (recovery?.additionalAssetSets ?? []) }
}

struct Catalog {
  private struct Manifest: Decodable {
    let schemaVersion: Int
    let features: [String: Feature]
    let assetTypes: [String: String]
    let modelDisplay: [String: ModelDisplay]?
    // These dependencies may be downloaded but are excluded from cleanup
    let recoveryAssetTypes: [String: String]?
    let preferenceUUIDs: [String: String]
  }

  private let manifest: Manifest
  private let consumersByAssetSet: [String: [String]]
  let featureNames: [String]

  var features: [String: Feature] { manifest.features }
  var assetTypes: [String: String] { manifest.assetTypes }
  var preferenceUUIDs: [String: String] { manifest.preferenceUUIDs }

  // Domains with a payload UUID can also be exported as forced preferences
  func hasProfileControls(_ feature: Feature) -> Bool {
    !feature.restrictions.isEmpty || feature.preferences.contains {
      preferenceUUIDs[$0.domain] != nil
    }
  }

  func controls(for feature: Feature) -> [String] {
    [
      ("preferences", !feature.preferences.isEmpty),
      ("profile", hasProfileControls(feature)),
      ("MDM", !feature.declarations.isEmpty),
      ("models", !feature.assetSets.isEmpty),
    ].compactMap { label, present in present ? label : nil }
  }

  var presentations: [FeaturePresentation] { featureNames.map(presentation) }

  func modelAsset(_ name: String, includingDownloadDependencies: Bool = false)
    throws(CLIError) -> ModelAssetSet
  {
    guard
      let assetType = assetTypes[name]
        ?? (includingDownloadDependencies ? manifest.recoveryAssetTypes?[name] : nil)
    else { throw CLIError("Missing asset type in the catalog for \(name); no request sent") }
    return ModelAssetSet(name: name, assetType: assetType)
  }

  func modelAssets(_ names: [String], includingDownloadDependencies: Bool = false)
    throws(CLIError) -> [ModelAssetSet]
  {
    try names.map { name throws(CLIError) in
      try modelAsset(name, includingDownloadDependencies: includingDownloadDependencies)
    }
  }

  func selectedFeatureNames(_ requested: [String], defaultingToAll: Bool = false)
    throws(CLIError) -> [String]
  {
    if requested.isEmpty { return defaultingToAll ? featureNames : [] }
    if requested.contains("all") {
      guard requested == ["all"] else { throw CLIError("Use 'all' alone") }
      return featureNames
    }
    try validateFeatureNames(requested)
    return Set(requested).sorted()
  }

  func validateFeatureNames(_ names: some Sequence<String>) throws(CLIError) {
    if let unknown = names.first(where: { features[$0] == nil }) {
      throw CLIError("Unknown feature: \(unknown)")
    }
  }

  func assetSets(
    for names: some Sequence<String>, at keyPath: KeyPath<Feature, [String]> = \.assetSets
  ) -> [String] {
    Set(names.lazy.flatMap { features[$0]![keyPath: keyPath] }).sorted()
  }

  func consumers(of assetSet: String) -> [String] {
    consumersByAssetSet[assetSet] ?? []
  }

  func presentation(_ name: String) -> FeaturePresentation {
    FeaturePresentation(name, feature: features[name])
  }

  func modelTitle(_ assetSet: String, wizard: Bool = false) -> String {
    guard let display = manifest.modelDisplay?[assetSet] else { return assetSet }
    return wizard ? display.wizardTitle : display.title
  }

  static func load() throws -> Catalog {
    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
      throw CLIError("Feature catalog is missing")
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    return try Catalog(manifest)
  }

  private init(_ manifest: Manifest) throws(CLIError) {
    guard manifest.schemaVersion == 1 else {
      throw CLIError("Unsupported catalog schema version: \(manifest.schemaVersion)")
    }
    let recoveryTypes = manifest.recoveryAssetTypes ?? [:]
    guard recoveryTypes.keys.allSatisfy({ manifest.assetTypes[$0] == nil })
    else { throw CLIError("Cleanup and download-only asset types must be disjoint") }

    let names = manifest.features.keys.sorted()
    var consumers: [String: [String]] = [:]
    for name in names {
      let feature = manifest.features[name]!
      guard Set(feature.preferences.lazy.map(\.id)).count == feature.preferences.count else {
        throw CLIError("Duplicate preference mappings for \(name)")
      }
      guard feature.assetSets.allSatisfy({ manifest.assetTypes[$0] != nil })
      else { throw CLIError("Incomplete catalog mappings for \(name)") }
      if let recovery = feature.recovery {
        let allowed = Set(feature.downloadAssetSets)
        guard !recovery.name.isEmpty, !recovery.subscriber.isEmpty,
          !recovery.usageAliases.isEmpty || !(recovery.assetSetUsages ?? [:]).isEmpty,
          allowed.allSatisfy({ manifest.assetTypes[$0] != nil || recoveryTypes[$0] != nil }),
          allowed.isSuperset(of: (recovery.assetSetUsages ?? [:]).keys)
        else { throw CLIError("Incomplete recovery mappings for \(name)") }
      }
      // Match each consumer once and preserve the catalog's feature order
      for assetSet in feature.assetSets where consumers[assetSet]?.last != name {
        consumers[assetSet, default: []].append(name)
      }
    }
    self.manifest = manifest
    featureNames = names
    consumersByAssetSet = consumers
  }
}

struct CLIError: LocalizedError, CustomStringConvertible {
  let description: String
  var errorDescription: String? { description }
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
