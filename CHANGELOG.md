# Changelog

## Unreleased

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
