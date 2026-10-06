# Pared from the terminal

Choose your features, install the matching profile, then remove models you no
longer need. Run `pared wizard` for guided setup or follow the commands below.
Pared requires an Apple silicon Mac (M1 or newer) running macOS 27 or newer.

## Install

### Guided installer

The installer becomes available with the first prebuilt release. Once published,
open **Terminal** from Applications -\> Utilities and run:

```sh
curl --fail --location --proto '=https' --proto-redir '=https' \
  --output "$HOME/Downloads/pared-install.sh" \
  https://github.com/4evy/pared/releases/latest/download/install.sh &&
sh "$HOME/Downloads/pared-install.sh"
```

The installer checks the CLI archive’s SHA-256 checksum and opens the wizard.
The prebuilt CLI needs no Swift, Xcode, or Homebrew.

Choose **Install Pared** to install in `~/.local` or another directory. If you
add Pared to your shell’s `PATH`, open a new terminal window afterward. Updating
keeps your policy and refuses to overwrite an unrelated installation.

For offline installation, download `install.sh`, `pared-macos-arm64.tar.gz`, and
`pared-macos-arm64.tar.gz.sha256` from the same release into one folder:

```sh
sh install.sh --archive ./pared-macos-arm64.tar.gz
```

Put `--archive` first. Remaining arguments go to the wizard:
`--prefix /full/path` suggests an installation directory, and `--policy FILE`
opens a policy. Run `sh install.sh --help` for all options.

### Homebrew

Install Xcode 27 or newer, then run:

```sh
brew tap 4evy/pared https://github.com/4evy/pared.git
brew install 4evy/pared/pared
```

### Nix

With Nix flakes enabled:

```sh
nix run github:4evy/pared -- status
nix profile install github:4evy/pared
```

From a local checkout, `nix build` produces `./result/bin/pared`.

## Guided setup

Run `pared wizard` and choose **Guided setup** for feature choices, profile
installation, optional model removal, and CLI installation. You can skip steps
or return to the menu; completed actions are kept.

Use arrow keys and Enter to navigate, Space to select features, and `/` to
search. Choose **Change more features** to combine choices, such as turning all
features off and then turning Writing Tools back on. Changes stay in a draft
until you save; discarding the draft changes nothing.

A new policy starts with every feature disabled. Review the full draft before
saving. Opening the wizard changes nothing; model removal has a separate preview
and confirmation. Finish profile installation in System Settings.

Use `pared wizard --policy /path/to/policy.json` to open or create a policy. Run
`pared wizard --help` for options. The terminal must be at least 40 columns wide
and 16 rows tall. Confirmations default to No.

The wizard’s cleanup preview lists eligible model groups; it does not measure
their size or recovered disk space.

## Inspect your settings

```sh
pared features
pared status
```

`features` lists names you can use in commands. `status` shows your saved
choices and the preferences Pared can read; it does not verify runtime
enforcement. These choices form a *policy*, stored by default at
`~/Library/Application Support/pared/policy.json`.

Use `--policy FILE` with a command to read a policy at another path.

## Choose features and install the profile

Starting with a new policy, this enables Writing Tools and leaves every other
feature disabled:

```sh
pared enable writingTools
pared profile open
```

Finish installing the generated profile in System Settings. It applies supported
controls and blocks downloads for model groups whose known features are all
disabled. Replace it whenever you change feature choices: the installed profile
keeps its settings until you replace or remove it. See the [profile
compatibility notes](how-it-works.md#profile-compatibility) for controls that
require MDM.

`enable`, `disable`, and `reset` save choices and apply supported local
preferences. Enabling a feature keeps its models but does not download missing
ones. Changing choices does not delete models.

## Remove downloaded models

After installing the matching profile, preview removal:

```sh
pared models cleanup --dry-run
```

When you are ready, run removal. This command does not ask for confirmation:

```sh
pared models cleanup
```

Only groups whose known features are all disabled are selected. Shared models
stay when any feature in Pared’s catalog is enabled or unmanaged.

Pared checks the selected model folders after Apple’s service replies. Cleanup
fails if any remain or cannot be inspected. If models are still in use, close
affected apps, log out or restart, then run `pared models status` before
retrying.

Keep the matching profile installed to block future downloads. The folder check
does not measure recovered APFS disk space; System Settings may update its
storage total later. A timed-out request may still have changed models; check
their status before retrying.

## Keep Siri

To keep Siri while disabling other features:

```sh
pared disable all
pared enable siri siriVoiceTrigger
pared profile open
```

Install the updated profile, then check Siri in System Settings -\> Apple
Intelligence & Siri. `siriVoiceTrigger` controls voice activation separately;
omit it if you only want keyboard activation.

Keeping Siri enabled or unmanaged keeps its shared foundation models; basic Siri
is not guaranteed to work if you delete them. Siri-related services also serve
other macOS features, so a running process alone does not show that Siri is on.

## Let an app use its defaults

To stop managing a feature, remove its local preference overrides and replace
the profile:

```sh
pared reset inlinePredictions
pared profile open
```

`reset` leaves the feature unmanaged and removes its local preference overrides.
It does not restore values from before Pared ran. Apple supplies defaults where
no other policy applies.

## Download models again

Enable the feature and install the replacement profile before requesting its
models. For a feature with a download mapping, such as Genmoji:

```sh
pared enable genmoji
pared profile open
# Finish installing the profile in System Settings before continuing
pared models download genmoji
pared models status genmoji
```

Success means Apple’s service accepted the download subscription. Downloads run
in the background; `models status` shows a snapshot and local directories, not
live progress. For features without a download mapping, turn them on in their
Apple app.

## Open the macOS app

Run `pared gui` to open the native interface. Use **File -\> Open Settings
File** or `pared gui --policy FILE` to inspect another policy. Policies in
`/nix/store` are read-only in the app; change them in Nix and rebuild.

To build a Finder app from this checkout with Xcode 27 or newer:

```sh
tools/build-app.sh
open .build/Pared.app
```

## Use a Nix-managed policy

The CLI uses its own policy unless you pass `--policy`. For nix-darwin, preview
cleanup using the generated policy with:

```sh
pared models cleanup --policy /etc/pared/policy.json --dry-run
```

Home Manager puts its policy in `$XDG_CONFIG_HOME/pared`, usually
`~/.config/pared`. Change Nix-managed choices in your Nix configuration and
rebuild; CLI edits to a policy in `/nix/store` are rejected.

Alongside the policy, `disable-apple-intelligence.mobileconfig` is the profile
to install in System Settings. `declarations.json` is for supervised mobile
device management (MDM) enrollment and cannot be installed there.

Both Nix modules remove eligible models during activation by default. They skip
cleanup when the policy matches the last successful cleanup. A changed policy or
failed cleanup triggers another attempt on activation. Set
`programs.pared.cleanupOnActivation = false;` to opt out.

Home Manager respects activation dry runs and keeps its cleanup record under
`$XDG_STATE_HOME/pared`; nix-darwin uses `/var/db/pared`. Activation does not
install the profile. Follow the [Nix setup
guide](https://4evy.github.io/pared/docs/#quick-start) for configuration.

Run `pared --help` for all commands. Read [how profiles and model removal
work](how-it-works.md) for implementation details.
