import Foundation

enum FeatureState: String, CaseIterable, Codable {
  case enabled, disabled, unmanaged
}

struct Policy: Codable, Equatable {
  static let supportedSchemaVersion = 1
  var schemaVersion = supportedSchemaVersion
  var defaultState: FeatureState = .disabled
  var features: [String: FeatureState] = [:]

  func state(_ name: String) -> FeatureState { features[name, default: defaultState] }

  mutating func set(_ state: FeatureState, for names: some Sequence<String>) {
    features.merge(names.map { ($0, state) }) { _, requested in requested }
  }

  func managedFeatures(in catalog: Catalog) -> [String: Feature] {
    catalog.features.filter { state($0.key) != .unmanaged }
  }

  func changedFeatureNames(from original: Policy, in catalog: Catalog) -> [String] {
    catalog.featureNames.filter { state($0) != original.state($0) }
  }

  func validate(_ catalog: Catalog) throws(CLIError) {
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
    if !explicit {
      var candidate = url
      while true {
        do {
          // Unlike fileExists, this preserves denied access and dangling links
          _ = try FileManager.default.attributesOfItem(atPath: candidate.path)
          if candidate == url { break }
          // A missing policy behind a broken directory link is not a new policy
          var isDirectory: ObjCBool = false
          guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
            isDirectory.boolValue
          else { throw CLIError("Policy directory is unavailable: \(candidate.path)") }
          return Policy()
        } catch {
          let fileError = error as NSError
          let underlying = fileError.userInfo[NSUnderlyingErrorKey] as? NSError
          guard candidate.path != "/", fileError.domain == NSCocoaErrorDomain,
            fileError.code == NSFileReadNoSuchFileError,
            underlying == nil
              || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT))
          else { throw error }
          candidate = candidate.deletingLastPathComponent()
        }
      }
    }
    let policy = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: url))
    try policy.validate(catalog)
    return policy
  }

  func save(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try jsonData(self).write(to: url, options: .atomic)
  }

  // Remove a shared model only when every consumer in the catalog is disabled
  // This protects known consumers; the catalog may omit Apple dependencies
  func cleanupTargets(_ catalog: Catalog) -> [String] {
    catalog.assetTypes.keys.filter { assetSet in
      let consumers = catalog.consumers(of: assetSet)
      return !consumers.isEmpty && consumers.allSatisfy { state($0) == .disabled }
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
