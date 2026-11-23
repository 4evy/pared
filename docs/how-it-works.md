# How Pared manages settings and models

Pared applies feature settings and removes models through Apple’s asset service.
These actions happen separately:

1. **Save choices.** Saving your policy applies supported local preferences and
   generates a profile
2. **Install the profile.** macOS applies its supported managed controls.
   Replace it whenever you change choices
3. **Remove models.** Cleanup requests removal and checks model folders
   afterward

The CLI, wizard, app, and Nix modules share a [feature
catalog](../Sources/Pared/Resources/catalog.json) that maps features to settings
and model groups. Apple manages each model group as an *asset set*.

## Select model groups

An asset set is eligible for removal only when every known consumer is disabled.
For example, keeping Siri enabled or unmanaged keeps its shared foundation
models. The catalog protects known consumers. Apple may have dependencies it
does not cover.

## Profile compatibility

The profile combines legacy restrictions and forced preferences. Apple
[deprecated the Apple Intelligence and Siri restriction keys](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.applicationaccess.yaml)
in macOS 26.4. Installing Pared’s profile does not establish that macOS honors
those keys. Forced preferences work independently of them.

Pared exports replacement Intelligence, External Intelligence, and Siri
declarations for
[supervised mobile device management (MDM) enrollment](https://developer.apple.com/documentation/devicemanagement/intelligencesettings);
System Settings cannot install them.

## Replace older profiles before updating macOS

Older Pared profiles redirected model downloads to a loopback address using
`DownloadServerBaseURLOverride-<assetType>` in `com.apple.MobileAsset`.
The override is keyed by asset type, not by what requested the download.
Software Update can stage assets of those same types. The current profile
omits the redirects and keeps its feature controls.

Use `pared profile open` and install the replacement in System Settings →
General → Device Management. If Software Update is already stuck, remove the
old profile and retry the update. Rebuilding a Nix configuration or updating
Pared does not replace an installed profile.

Pared does not install a download block. The private MobileAsset scheduler
allowlist affects unrelated asset types and does not cover every download
path. Feature restrictions control use, not which assets macOS can stage.
If models return after an update, run `pared models cleanup --dry-run` to
review which sets you can remove again.

## Connect to Apple’s asset service

Apple’s daemon can remove protected assets, so Pared leaves System Integrity
Protection (SIP) enabled.

Pared loads `UnifiedAssetFramework` with `dlopen` and opens an `NSXPCConnection`
to `com.apple.siri.uaf.subscription.service`. Its Swift bridge calls
`operationWithConfig:completion:` through Apple’s
`UAFXPCProxyServiceInterface.defaultInterface` to preserve the XPC signature and
allowed object classes. The bridge rejects unknown signatures and metadata
instead of treating them as empty results.

## Remove downloaded models

Pared checks each selected set’s `autoAssetType` in `UAFConfigurationManager`
against its catalog; a mismatch stops removal. It then removes matching
`org.pared` download subscriptions and sends a scoped reset. For example:

```json
{
  "Operation": "ResetAssetSets",
  "AssetSets": ["com.apple.modelcatalog"]
}
```

`AssetSets` is always explicit because omitting it resets *every* set. Reset
affects the selected sets for all users; subscriptions owned by Apple or other
apps remain.

A successful reply means the service returned without an error. Cleanup then
fails if selected model folders remain or cannot be inspected. Folder removal
does not measure recovered APFS disk space. A timeout or connection failure
leaves the request’s outcome unknown.

## Download models again

Enable the feature and install the replacement profile before requesting its
models. Changing local preferences alone does not lift installed restrictions
or download redirects from an older profile.

Pared resolves usage aliases, checks usage names against Apple’s configuration,
and builds `UAFAssetSetSubscription` objects with
`initWithName:assetSets:usageAliases:`. It sends `Unsubscribe` followed by
`Subscribe`: reset can leave subscription records behind, and Apple skips
identical subscriptions. These are separate requests, so a failed refresh can
leave partial changes.

Apple handles downloads in the background. Acceptance does not confirm
completion; `pared models status` shows a snapshot and local model directories.

## Compatibility limits

Private macOS APIs can change between releases. Runtime checks detect
unsupported interfaces; they cannot guarantee unchanged service behavior.

For commands and troubleshooting, see the [command-line guide](cli.md).
