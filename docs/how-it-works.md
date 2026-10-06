# How Pared manages settings and models

Pared applies feature settings, blocks unwanted downloads, and removes models
through Apple’s asset service. These actions happen separately:

1. **Save choices.** Saving your policy applies supported local preferences and
   generates a profile
2. **Install the profile.** macOS applies its supported managed controls and
   download blocks. Replace it whenever you change choices
3. **Remove models.** Cleanup requests removal and checks model folders
   afterward

The CLI, wizard, app, and Nix modules share a [feature
catalog](../Sources/Pared/Resources/catalog.json) that maps features to settings
and model groups. Apple manages each model group as an *asset set*.

## Select model groups

An asset set is eligible for removal and download blocking only when every known
consumer is disabled. For example, keeping Siri enabled or unmanaged keeps its
shared foundation models. The catalog protects known consumers; Apple may have
dependencies it does not cover.

## Profile compatibility

The profile combines legacy restrictions, forced preferences, and download
blocks. Apple [deprecated the Apple Intelligence and Siri restriction
keys](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.applicationaccess.yaml)
in macOS 26.4. Installing Pared’s profile does not establish that macOS honors
those keys. Forced preferences and download blocks work independently of them.

Pared exports replacement Intelligence, External Intelligence, and Siri
declarations for [supervised mobile device management (MDM)
enrollment](https://developer.apple.com/documentation/devicemanagement/intelligencesettings);
System Settings cannot install them.

## Block future downloads

For each selected asset set, the profile redirects its asset type’s downloads to
the loopback URL `https://127.0.0.1:9/pared-blocked/`. It sets
`DownloadServerBaseURLOverride-<assetType>` in `com.apple.MobileAsset`.

The download daemon, `mobileassetd`, reads these values from
`/Library/Managed Preferences/com.apple.MobileAsset.plist`. Its sandbox denies
ordinary system `defaults`, which is why blocking needs a managed profile.
Catalog checks and local retries can continue while payload downloads are
blocked.

## Connect to Apple’s asset service

Apple’s daemon can remove protected assets, so Pared leaves System Integrity
Protection (SIP) enabled.

Pared loads `UnifiedAssetFramework` with `dlopen` and opens an `NSXPCConnection`
to `com.apple.siri.uaf.subscription.service`. Its Objective-C bridge calls
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

Enable the feature and replace the profile before requesting its models. The
replacement omits blocks for asset sets with enabled or unmanaged consumers;
changing local preferences alone leaves the installed blocks in place.

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
