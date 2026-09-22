import Foundation

func preferenceValues(policy: Policy, catalog: Catalog) -> [String: [String: ManagementValue]] {
  var values: [String: [String: ManagementValue]] = [:]
  for (name, feature) in catalog.features where policy.state(name) != .unmanaged {
    for preference in feature.preferences {
      values[preference.domain, default: [:]][preference.key] =
        .boolean((policy.state(name) == .enabled) != preference.inverted)
    }
  }
  // mobileassetd reads its managed preferences directly. Ordinary
  // defaults are sandbox-denied. The same shared-consumer rule governs removal
  // and blocking; enabled or unmanaged consumers must retain download access.
  let block = catalog.downloadBlocking
  for assetSet in policy.cleanupTargets(catalog) {
    let key = block.keyPrefix + catalog.assetTypes[assetSet]!
    values[block.domain, default: [:]][key] = .string(block.url)
  }
  return values
}

enum ProfileIdentity {
  static let identifier = "org.pared.disable-apple-intelligence"
  static let uuid = "FBB914A9-6F77-45AE-9503-950B247DBB50"
  static let restrictionsUUID = "E7288120-8944-4A2E-A822-28123EE79F57"
  static let payloadVersion = 1
}

// Property lists and declaration trees have dynamic catalog keys but a small,
// known set of value types. Avoid allowing arbitrary objects into either format
indirect enum ManagementValue: Encodable {
  case string(String)
  case integer(Int)
  case boolean(Bool)
  case object([String: ManagementValue])
  case array([ManagementValue])

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    }
  }
}

private func payload(
  type: String, identifier: String, uuid: String, displayName: String
) -> [String: ManagementValue] {
  [
    "PayloadType": .string(type), "PayloadVersion": .integer(ProfileIdentity.payloadVersion),
    "PayloadIdentifier": .string(identifier), "PayloadUUID": .string(uuid),
    "PayloadDisplayName": .string(displayName),
  ]
}

func profileData(policy: Policy, catalog: Catalog) throws -> Data {
  var restrictions = payload(
    type: "com.apple.applicationaccess",
    identifier: ProfileIdentity.identifier + ".restrictions",
    uuid: ProfileIdentity.restrictionsUUID, displayName: "Apple Intelligence restrictions")
  for (name, feature) in catalog.features where policy.state(name) != .unmanaged {
    for key in feature.restrictions { restrictions[key] = .boolean(policy.state(name) == .enabled) }
  }
  let values = preferenceValues(policy: policy, catalog: catalog)
  // Each domain needs its own Forced payload
  let preferencePayloads: [ManagementValue] = values.sorted(by: { $0.key < $1.key }).map {
    domain, settings in
    var preferences = payload(
      type: "com.apple.ManagedClient.preferences",
      identifier: ProfileIdentity.identifier + ".preferences." + domain,
      uuid: catalog.preferenceUUIDs[domain]!, displayName: "AI preferences: \(domain)")
    preferences["PayloadContent"] = .object([
      domain: .object([
        "Forced": .array([
          .object(["mcx_preference_settings": .object(settings)])
        ])
      ])
    ])
    return .object(preferences)
  }
  var profile = payload(
    type: "Configuration", identifier: ProfileIdentity.identifier,
    uuid: ProfileIdentity.uuid, displayName: "pared Apple Intelligence policy")
  profile["PayloadDescription"] = .string("Manage Apple Intelligence features; preserve dictation.")
  profile["PayloadScope"] = .string("System")
  profile["PayloadContent"] = .array([.object(restrictions)] + preferencePayloads)
  let encoder = PropertyListEncoder()
  encoder.outputFormat = .xml
  return try encoder.encode(profile)
}

private func setPath(
  _ parts: ArraySlice<String>, value: Bool, in object: inout [String: ManagementValue]
) {
  guard let part = parts.first else { return }
  let key = part
  if parts.count == 1 {
    object[key] = .boolean(value)
    return
  }
  var child: [String: ManagementValue] = [:]
  if case .object(let existing) = object[key] { child = existing }
  setPath(parts.dropFirst(), value: value, in: &child)
  object[key] = .object(child)
}

enum DeclarationGroup: String, CaseIterable {
  case intelligence, external

  var identifier: String {
    switch self {
    case .intelligence: return "intelligence"
    case .external: return "external-intelligence"
    }
  }
}

private struct ManagementDeclaration: Encodable {
  let type: String
  let identifier: String
  let payload: ManagementValue

  enum CodingKeys: String, CodingKey {
    case type = "Type"
    case identifier = "Identifier"
    case payload = "Payload"
  }
}

// Apple schemas: github.com/apple/device-management, release branch:
// declarative/declarations/configurations/{intelligence,external-intelligence}.settings.yaml
// Declarations require supervised MDM on 26.4+; Visual Intelligence and Calendar
// require 27+. These are MDM configurations, not installable mobileconfigs
func declarationData(policy: Policy, catalog: Catalog) throws -> Data {
  var groups: [String: ManagementValue] = [:]
  for (name, feature) in catalog.features where policy.state(name) != .unmanaged {
    for path in feature.declarations {
      setPath(
        ([path.group.rawValue] + path.components)[...], value: policy.state(name) == .enabled,
        in: &groups)
    }
  }
  let declarations = DeclarationGroup.allCases.compactMap { group -> ManagementDeclaration? in
    guard let payload = groups[group.rawValue] else { return nil }
    return ManagementDeclaration(
      type: "com.apple.configuration.\(group.identifier).settings",
      identifier: "org.pared.\(group.identifier)", payload: payload)
  }
  return try jsonData(declarations)
}
