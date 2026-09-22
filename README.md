<!-- rumdl-disable MD033 -->

<h1 align="center">pared</h1>

<p align="center">
  Remove Apple Intelligence models you don't use<br>
  <strong>SIP stays on. No Recovery reboot</strong>
</p>

<p align="center">
  <a href="#install"><img src="https://img.shields.io/badge/macOS-27+-000000?logo=apple" alt="macOS 27 or newer"></a>
  <a href="#how-it-works"><img src="https://img.shields.io/badge/SIP-enabled-2ea44f" alt="SIP stays enabled"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#use">Usage</a> ·
  <a href="#similar-projects">Compare</a> ·
  <a href="https://4evy.github.io/pared/">Nix documentation</a>
</p>

Turn off the Apple Intelligence features you don't want and clean up their
models from the CLI, nix-darwin, or Home Manager.

## Install

### Homebrew

Requires macOS 27 and Xcode 27 or newer.

```sh
brew tap 4evy/pared https://github.com/4evy/pared.git
brew install 4evy/pared/pared
```

### Nix

On Apple silicon, with Nix flakes enabled:

```sh
nix run github:4evy/pared -- status
nix profile install github:4evy/pared
```

From a local checkout, run `nix build` and `./result/bin/pared --help`.

## Use

```sh
pared features                              # List available features
pared status                                # Show current settings
pared disable siri notificationSummaries
pared enable writingTools
pared reset inlinePredictions               # Restore Apple's defaults
pared profile open                          # Open the updated profile
pared models cleanup --dry-run              # Preview model cleanup
```

After changing your settings, install the updated profile in System Settings.
`enable`, `disable`, and `reset` save your desired policy even while the old
profile is installed. Its settings remain enforced until you replace it.
The profile blocks model downloads for disabled features. Run
`pared models cleanup` once to remove existing models. The Nix modules also
run cleanup during activation by default. Run `pared --help` for the full
command list.

## nix-darwin / Home Manager

Add `inputs.pared.url = "github:4evy/pared";` to your flake. Choose one of the
modules below.

### nix-darwin

Pass `inputs` through `specialArgs`, then add this to your Darwin config:

```nix
{ inputs, ... }:
{
  imports = [ inputs.pared.darwinModules.default ];

  programs.pared = {
    enable = true;
    defaultState = false;
    features = {
      writingTools = true;
      notificationSummaries = false;
      spatialPhotos = null;
    };
  };
}
```

### Home Manager

Pass `inputs` through `extraSpecialArgs`, then add this to your home config:

```nix
{ inputs, ... }:
{
  imports = [ inputs.pared.homeManagerModules.default ];

  programs.pared = {
    enable = true;
    defaultState = false;
    features = {
      writingTools = true;
      notificationSummaries = false;
      spatialPhotos = null;
    };
  };
}
```

`true` turns a feature on, `false` turns it off, and `null` leaves it unmanaged.
Features you don't list use `defaultState`. Rebuild your config and install the
profile from `/etc/pared` (nix-darwin) or `$XDG_CONFIG_HOME/pared`
(Home Manager, normally `~/.config/pared`).

Both modules remove models for disabled features during activation by default.
They record the last successfully cleaned policy and skip cleanup when it is
unchanged. A policy change triggers cleanup again; failures retry on the next
activation. Set `programs.pared.cleanupOnActivation = false;` to opt out.
Home Manager respects activation dry runs and keeps its cleanup record under
`$XDG_STATE_HOME/pared`; nix-darwin uses `/var/db/pared`.

Cleanup does not install the profile. Install it to block future model
downloads.

## How it works

Profiles and preferences control which features are enabled. The installed
profile prevents new model payload downloads; explicit cleanup removes existing
models through Apple's asset service. Shared models remain downloadable if any
of their known consumers are enabled or left unmanaged.

<details>
<summary>Under the hood</summary>

**Feature settings.** The [catalog](Sources/Pared/Resources/catalog.json) maps
features to preference domains, restriction keys, and asset sets. Pared writes
preferences and generates `.mobileconfig` profiles and MDM declarations from
that map. The Nix modules use the same catalog to generate settings and
profiles.

**Preventing downloads.** For each asset type whose known consumers are all
disabled, the profile sets `DownloadServerBaseURLOverride-<assetType>` in
`com.apple.MobileAsset` to `https://127.0.0.1:9/pared-blocked/`.
`mobileassetd` reads these settings from
`/Library/Managed Preferences/com.apple.MobileAsset.plist`; ordinary system
`defaults` are denied by its sandbox. Catalog checks and local retries can
continue, but model payloads cannot download from Apple.

**The XPC connection.** Pared loads `UnifiedAssetFramework` with `dlopen` and
connects to `com.apple.siri.uaf.subscription.service` using `NSXPCConnection`.
It calls `operationWithConfig:completion:` through Apple's
`UAFXPCProxyServiceInterface.defaultInterface`, which supplies the wire
signature and allowed object classes. The Objective-C bridge declares the
`oneway void` operation and typed configuration getters; Swift does not
invoke these selectors through `perform`. Runtime shape checks reject unknown
asset metadata instead of treating it as an empty result.

**Deleting models.** Pared groups features by asset set and selects a set only
when every known consumer is disabled in your policy. It reads each set's
`autoAssetType` from `UAFConfigurationManager` and checks it against the
catalog, then removes matching `org.pared` download subscriptions and sends a
reset
request like this:

```json
{
  "Operation": "ResetAssetSets",
  "AssetSets": ["com.apple.modelcatalog"]
}
```

`AssetSets` is always explicit: omitting it means *every* asset set to the
server. The daemon resets those sets and calls MobileAsset's
`eliminateAllForAssetTypeSync:`. Apple's daemon has the entitlements to delete
protected assets, so SIP stays on.

**Downloading again.** Enable the feature and install the replacement profile
before requesting a download. The replacement omits blocks for enabled or
unmanaged consumers. Resetting a CLI preference alone does not replace an
installed profile. Removing the profile removes its managed download blocks.

Pared resolves usage aliases and checks explicit usage
names against Apple's configuration, then builds `UAFAssetSetSubscription`
objects with `initWithName:assetSets:usageAliases:`. It sends `Unsubscribe`
followed by `Subscribe` to refresh the selected subscriptions, since reset
removes assets but can leave their subscription records behind. Apple's service
then handles the download in the background.

</details>

## Similar projects

These tools use direct file deletion instead of Apple's asset service:

- [Unintelligence][unintelligence]: a SwiftUI app that falls back to Recovery
  for protected models.
- [Delete Apple Intelligence][delete-ai]: a manual removal guide that has you
  temporarily disable SIP.
- [Apple Intelligence Remover][ai-remover]: a shell tool with a Recovery script
  for protected models.

[unintelligence]: https://github.com/Rismaonee/Unintelligence
[delete-ai]: https://github.com/tejyash/delete-apple-intelligence-macos
[ai-remover]: https://github.com/minagishl/apple-intelligence-remover

## Reference

- [Nix option reference](https://4evy.github.io/pared/)
- [Feature catalog](Sources/Pared/Resources/catalog.json)
