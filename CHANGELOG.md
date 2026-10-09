# Changelog

## Unreleased

### Changed

- Private asset operations use checked service connections and validate native
  method and XPC forwarding signatures before dispatch
- Model inventory uses typed diagnostic records and published catalog metadata,
  preserving the distinction between JSON booleans and numbers when matching
  assets

### Fixed

- Private asset calls use Intel's native BOOL convention and report unsupported
  status getter signatures instead of calling them unchecked
- Model inventory rejects malformed diagnostic records without silently dropping
  assets and includes diagnostic errors and completeness in its JSON report
- Published catalog queries omit the hardcoded certificate issuance date and
  validate Apple's DER signature format, envelope encoding, and audience

## 2.1.0 — 2026-10-08

### Added

- `pared models inventory` for daemon-reported asset paths and parsed metadata,
  supplemented with matching metadata from Apple's published catalogs
- `pared models holders` for inspecting apps and services with selected model
  files open
- Model-holder review after unsuccessful cleanup in the app and wizard, with
  administrator inspection, normal app quit, and a reviewed force-quit option
  that retries removal once

### Changed

- Cleanup distinguishes remaining model folders (exit 1) from unavailable
  verification after an accepted removal request (exit 3), with folder access
  guidance and separate reporting of daemon elimination evidence
- The private Apple asset bridge is implemented in Swift, retaining runtime
  method-signature and value checks
- Build, release, inspection, and demo tools are grouped into named directories

### Fixed

- Model inventory can verify empty protected folders or use daemon-reported
  paths when filesystem metadata accounts for every directory entry
- Model status skips the download snapshot query when no payloads remain,
  avoiding errors from an absent atomic-instance lock file
- Cleanup succeeds when every selected model folder is confirmed gone, even if
  macOS retained an earlier lock error after forced removal
- App diagnostics preserve CLI error descriptions

## 2.0.0 — 2026-10-06

### Added

- A native macOS app with an overview, feature choices, model management, and
  configuration profile setup, available from Finder or `pared gui`
- A `pared wizard` guided setup for choosing features, installing the profile,
  reviewing model removal, and installing the CLI
- A bootstrap installer that downloads and checks a prebuilt CLI release, with
  support for offline archives
- An offline changelog in the app and a link to published releases
- Sparkle app updates with signed feeds and archives, daily checks, optional
  automatic installation on quit, and a manual **Check for Updates…** action
- A Siri MDM declaration and a profile restriction for external AI account
  sign-in
- A website landing page and expanded CLI and implementation documentation

### Changed

- Pared now requires macOS 27; building from source requires Swift 6.2.4 or
  newer
- The CLI and Finder app are packaged separately; Sparkle is included only in
  the Finder app
- App bundle versions use the release tag, or `VERSION` for local builds
- CLI argument handling uses Swift Argument Parser for command help, validation,
  and shell completion generation

### Fixed

- CLI installation from the app wizard installs the bundled standalone CLI,
  which runs independently of the app's Sparkle framework
- Model cleanup checks remaining model folders before reporting success and
  reports incomplete removal or unreadable folders as failures
- Model inventory treats a missing asset directory as empty and rejects symbolic
  links that could hide remaining models
- Profile status preserves daemon error details and rejects malformed metadata

## 1.0.0 — 2026-09-22

### Added

- A CLI for enabling, disabling, and resetting supported Apple Intelligence
  features
- Configuration profile and MDM declaration generation, installation guidance,
  and installed profile status
- Model status, removal previews, cleanup, and supported download requests
- Nix Darwin and Home Manager modules, a Homebrew formula, and a web manual
