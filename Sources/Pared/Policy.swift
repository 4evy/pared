import Foundation

enum FeatureState: String, Codable {
  case enabled, disabled, unmanaged
}

struct Policy: Codable {
  static let supportedSchemaVersion = 1
  var schemaVersion = supportedSchemaVersion
  var defaultState: FeatureState = .disabled
  var features: [String: FeatureState] = [:]

  func state(_ name: String) -> FeatureState { features[name, default: defaultState] }

  func validate(_ catalog: Catalog) throws {
    guard schemaVersion == Self.supportedSchemaVersion else {
      throw CLIError("Unsupported policy schema version: \(schemaVersion)")
    }
    for name in features.keys where catalog.features[name] == nil {
      throw CLIError("Unknown feature: \(name)")
    }
  }

  static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(Artifacts.applicationDirectory, isDirectory: true)
      .appendingPathComponent(Artifacts.policyFilename)
  }

  static func load(_ url: URL, explicit: Bool, catalog: Catalog) throws -> Policy {
    if !FileManager.default.fileExists(atPath: url.path) && !explicit { return Policy() }
    let policy = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: url))
    try policy.validate(catalog)
    return policy
  }

  func save(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try jsonData(self).write(to: url, options: .atomic)
  }

  // Preserve shared models whenever any known consumer is enabled or unmanaged
  // This is a conservative policy map, not a complete Apple dependency graph
  func cleanupTargets(_ catalog: Catalog) -> [String] {
    let consumers = Dictionary(
      grouping: catalog.features.flatMap { name, feature in
        feature.assetSets.map { (asset: $0, feature: name) }
      },
      by: \.asset)
    return catalog.assetTypes.keys.filter { asset in
      guard let consumers = consumers[asset] else { return false }
      return consumers.allSatisfy { state($0.feature) == .disabled }
    }.sorted()
  }
}

func jsonData<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  var data = try encoder.encode(value)
  data.append(0x0a)
  return data
}
