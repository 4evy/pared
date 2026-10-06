# Pared from the terminal

Run `pared wizard` for guided setup or use the commands below. Requires Apple
silicon and macOS 27 or newer.

## Install

### Guided installer

Run in Terminal:

```sh
curl --fail --location --proto '=https' --proto-redir '=https' \
  --output "$HOME/Downloads/pared-install.sh" \
  https://github.com/4evy/pared/releases/latest/download/install.sh &&
sh "$HOME/Downloads/pared-install.sh"
```

The installer verifies the CLI’s SHA-256 checksum and opens the wizard. No Xcode
or Homebrew needed.

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

Run `pared wizard` and choose **Guided setup**. It walks through feature
choices, profile installation, optional model removal, and CLI installation. You
can skip steps; completed actions are kept.

Use arrow keys and Enter to navigate, Space to select features, and `/` to
search. **Change more features** combines choices before saving. A new policy
starts with everything off; review the draft before saving or discard it to
leave settings unchanged. Model removal has a separate preview and confirmation.

Use `--policy FILE` to open or create another policy. The wizard needs a
terminal at least 40 columns wide and 16 rows tall. Confirmations default to No;
removal previews list model groups, not disk space.

## Inspect your settings

```sh
pared features
pared status
```

`features` lists names for commands. `status` shows saved choices and readable
preferences, not runtime enforcement. Choices form a *policy*, stored at
`~/Library/Application Support/pared/policy.json` by default. Use
`--policy FILE` with a command to select another path.

## Choose features and install the profile

Starting with a new policy, this enables Writing Tools and leaves every other
feature disabled:

```sh
pared enable writingTools
pared profile open
```

Install the profile in System Settings to apply supported controls and block
unwanted model downloads. Replace it after every change; its settings stay in
effect until replaced or removed. Some controls require device management; see
[profile compatibility](how-it-works.md#profile-compatibility).

`enable`, `disable`, and `reset` save choices and apply supported local
preferences. They do not download or remove models.

## Remove downloaded models

After installing the matching profile, preview removal:

```sh
pared models cleanup --dry-run
```

Remove them **without a confirmation prompt**:

```sh
pared models cleanup
```

Only groups whose known features are all disabled are removed. Shared models
stay if any feature in Pared’s catalog is enabled or unmanaged.

Cleanup fails if selected model folders remain or cannot be inspected. For
models still in use, close affected apps, log out or restart, then check
`pared models status` before retrying. Check status after timeouts too: removal
may already have happened.

Keep the profile installed to block new downloads. Pared checks folders, not
recovered APFS space; System Settings may update its storage total later.

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

To stop managing a feature:

```sh
pared reset inlinePredictions
pared profile open
```

Install the replacement profile to finish. `reset` removes local overrides; it
does not restore earlier values. Apple supplies defaults where no other policy
applies.

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

Success means Apple accepted the request; downloads continue in the background.
`models status` shows a snapshot and local folders, not live progress. For
features without a download mapping, turn them on in their Apple app.

## Open the macOS app

Run `pared gui` to open the native interface. Use **File -\> Open Settings
File** or `pared gui --policy FILE` to inspect another policy. Policies in
`/nix/store` are read-only in the app; change them in Nix and rebuild.

For source builds, see the [build instructions](../README.md#build-from-source).

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

Both modules clean up eligible models during activation, retrying after policy
changes or failures. Set `programs.pared.cleanupOnActivation = false;` to opt
out. Activation does not install the profile. See the [Nix setup
guide](https://4evy.github.io/pared/docs/#quick-start) for configuration.

Home Manager respects activation dry runs and stores its cleanup record in
`$XDG_STATE_HOME/pared`; nix-darwin uses `/var/db/pared`.

Run `pared --help` for all commands. Read [how profiles and model removal
work](how-it-works.md) for implementation details.
