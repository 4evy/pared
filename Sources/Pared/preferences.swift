import CoreFoundation
import Foundation

struct PreferenceStatus: Codable, Identifiable {
  let domain: String
  let key: String
  let value: Bool?
  let forced: Bool

  var id: Preference.ID { Preference.ID(domain: domain, key: key) }

  enum CodingKeys: String, CodingKey { case domain, key, value, forced }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(domain, forKey: .domain)
    try container.encode(key, forKey: .key)
    try container.encode(value, forKey: .value)
    try container.encode(forced, forKey: .forced)
  }
}

func preferenceStatus(_ preference: Preference) -> PreferenceStatus {
  let domain = preference.domain as CFString
  let key = preference.key as CFString
  let value = CFPreferencesCopyAppValue(key, domain) as? NSNumber
  return PreferenceStatus(
    domain: preference.domain, key: preference.key,
    value: value?.boolValue, forced: CFPreferencesAppValueIsForced(key, domain))
}

struct PreferenceAssignment {
  let featureName: String
  let preference: Preference
  let value: Bool
}

extension Policy {
  // Include unmanaged features only when removing their local overrides
  func preferenceAssignments(
    in catalog: Catalog, for names: some Sequence<String>, reset: Bool = false
  ) -> [PreferenceAssignment] {
    names.flatMap { name -> [PreferenceAssignment] in
      let state = state(name)
      guard reset || state != .unmanaged else { return [] }
      return catalog.features[name]!.preferences.map { preference in
        PreferenceAssignment(
          featureName: name, preference: preference,
          value: preference.value(for: state))
      }
    }
  }
}

func validateDownloadPreferences(policy: Policy, catalog: Catalog, names: [String])
  throws(CLIError)
{
  // Reject downloads that conflict with enforced preferences
  // Policy edits must still succeed so the user can generate a replacement
  // profile that permits the download
  for assignment in policy.preferenceAssignments(in: catalog, for: names) {
    let status = preferenceStatus(assignment.preference)
    if status.forced && status.value != assignment.value {
      throw CLIError(
        "\(assignment.featureName) is forced by a management profile; update or remove that profile first"
      )
    }
  }
}

func applyPreferences(policy: Policy, catalog: Catalog, names: [String], reset: Bool = false) throws
{
  for assignment in policy.preferenceAssignments(in: catalog, for: names, reset: reset) {
    let preference = assignment.preference
    // Write the requested local value even when the installed profile
    // overrides it; the new value takes effect after that override is removed
    if preferenceStatus(preference).forced {
      report("\(assignment.featureName) remains managed until the updated profile is installed")
    }
    CFPreferencesSetValue(
      preference.key as CFString, reset ? nil : NSNumber(value: assignment.value),
      preference.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    guard
      CFPreferencesSynchronize(
        preference.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    else {
      throw CLIError(
        "Could not synchronize \(preference.domain); earlier writes may have succeeded")
    }
  }
}
