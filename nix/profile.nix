{
  lib,
  policy ? import ./policy.nix { inherit lib; },
}:
let
  inherit (policy) restrictions managedPreferences;
  preferenceUUIDs = (lib.trivial.importJSON ../Sources/Pared/Resources/catalog.json).preferenceUUIDs;
in
lib.generators.toPlist { escape = true; } {
  PayloadType = "Configuration";
  PayloadVersion = 1;
  PayloadIdentifier = "org.pared.disable-apple-intelligence";
  PayloadUUID = "FBB914A9-6F77-45AE-9503-950B247DBB50";
  PayloadDisplayName = "pared Apple Intelligence policy";
  PayloadDescription = "Manage Apple Intelligence features; preserve dictation.";
  PayloadScope = "System";
  PayloadContent = [
    (
      restrictions
      // {
        PayloadType = "com.apple.applicationaccess";
        PayloadVersion = 1;
        PayloadIdentifier = "org.pared.disable-apple-intelligence.restrictions";
        PayloadUUID = "E7288120-8944-4A2E-A822-28123EE79F57";
        PayloadDisplayName = "Apple Intelligence restrictions";
      }
    )
  ]
  ++ lib.attrsets.mapAttrsToList (domain: preferences: {
    # Each domain needs its own managed-preferences payload
    PayloadType = "com.apple.ManagedClient.preferences";
    PayloadVersion = 1;
    PayloadIdentifier = "org.pared.disable-apple-intelligence.preferences.${domain}";
    PayloadUUID = preferenceUUIDs.${domain};
    PayloadDisplayName = "AI preferences: ${domain}";
    PayloadContent.${domain}.Forced = [ { mcx_preference_settings = preferences; } ];
  }) managedPreferences;
}
