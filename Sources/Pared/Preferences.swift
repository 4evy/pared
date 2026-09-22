import CoreFoundation
import Foundation

struct PreferenceStatus: Encodable {
  let domain: String
  let key: String
  let value: Bool?
  let forced: Bool

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

func validateDownloadPreferences(policy: Policy, catalog: Catalog, names: [String])
  throws
{
  // Downloads must respect effective managed settings. Saving desired policy
  // must not use this check: that would prevent generating its replacement.
  for name in names {
    guard policy.state(name) != .unmanaged else { continue }
    for preference in catalog.features[name]!.preferences {
      let status = preferenceStatus(preference)
      let desired = (policy.state(name) == .enabled) != preference.inverted
      if status.forced && status.value != desired {
        throw CLIError(
          "\(name) is forced by a management profile; update or remove that profile first")
      }
    }
  }
}

func applyPreferences(policy: Policy, catalog: Catalog, names: [String], reset: Bool = false) throws
{
  for name in names {
    let state = policy.state(name)
    guard reset || state != .unmanaged else { continue }
    for preference in catalog.features[name]!.preferences {
      // Save local intent even when an installed profile overrides it. Rejecting
      // here would prevent generating the replacement profile needed to change
      // that enforced value. Download validation remains strict.
      if preferenceStatus(preference).forced {
        report("\(name) remains managed until the updated profile is installed")
      }
      let value: CFPropertyList? =
        reset ? nil : NSNumber(value: (state == .enabled) != preference.inverted)
      CFPreferencesSetValue(
        preference.key as CFString, value, preference.domain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      guard
        CFPreferencesSynchronize(
          preference.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      else {
        throw CLIError(
          "Could not synchronize \(preference.domain); earlier writes may have succeeded")
      }
    }
  }
}
