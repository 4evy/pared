#!/usr/bin/env bash
set -eu

# Build a Finder-launchable app with a standalone CLI for the guided installer
cd "$(dirname "$0")/../.."
configuration="${1:-release}"
case "$configuration" in
debug | release) ;;
*)
	printf 'Usage: tools/app/app.sh [debug|release]\n' >&2
	exit 64
	;;
esac
repository_version="$(cat VERSION)"
version="${RELEASE_TAG:-$repository_version}"
printf '%s\n' "$version" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ { valid = 1 } END { exit !valid }' || {
	printf 'App version must have the form MAJOR.MINOR.PATCH\n' >&2
	exit 1
}
[ "$version" = "$repository_version" ] || {
	printf 'App version must match VERSION (%s)\n' "$repository_version" >&2
	exit 1
}
# Sparkle is resolved by the app package; the root package builds the CLI
swift build --force-resolved-versions -c "$configuration"
cli_directory="$(swift build --force-resolved-versions -c "$configuration" --show-bin-path)"
swift build --package-path App --force-resolved-versions -c "$configuration"
binary_directory="$(swift build --package-path App --force-resolved-versions -c "$configuration" --show-bin-path)"
sparkle="$(pwd)/App/.build/artifacts/sparkle/Sparkle"
app_directory="$(pwd)/.build/Pared.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
mkdir -p "$app_directory/Contents/Frameworks"
mkdir -p "$app_directory/Contents/Helpers"
cp "$cli_directory/pared" "$app_directory/Contents/Helpers/.pared-new"
mv -f "$app_directory/Contents/Helpers/.pared-new" "$app_directory/Contents/Helpers/pared"
codesign --force --sign - "$app_directory/Contents/Helpers/pared"
cp "$binary_directory/ParedApp" "$app_directory/Contents/MacOS/.pared-new"
mv -f "$app_directory/Contents/MacOS/.pared-new" "$app_directory/Contents/MacOS/pared"
# SwiftPM finds Bundle.module resources inside the app's Resources directory
for resources in "$binary_directory"/*.bundle; do
	[ -d "$resources" ] || continue
	destination="$app_directory/Contents/Resources/$(basename "$resources")"
	rm -rf "$destination"
	cp -R "$resources" "$destination"
done
cp CHANGELOG.md "$app_directory/Contents/Resources/CHANGELOG.md"
cp "$sparkle/LICENSE" "$app_directory/Contents/Resources/Sparkle-LICENSE.txt"
rm -rf "$app_directory/Contents/Frameworks/Sparkle.framework"
# Embed the framework SwiftPM linked, preserving its signed helpers and symlinks
cp -R "$binary_directory/Sparkle.framework" "$app_directory/Contents/Frameworks/"
rm -rf "$app_directory/Contents/PlugIns/ParedUpdater.bundle"
swift tools/app/icon.swift .build/Pared.iconset
iconutil --convert icns .build/Pared.iconset --output "$app_directory/Contents/Resources/AppIcon.icns"
cat >"$app_directory/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>pared</string>
  <key>CFBundleIdentifier</key><string>org.pared.app</string>
  <key>CFBundleName</key><string>Pared</string>
  <key>CFBundleDisplayName</key><string>Pared</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -insert CFBundleShortVersionString -string "$version" "$app_directory/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$version" "$app_directory/Contents/Info.plist"
plutil -insert SUFeedURL -string 'https://github.com/4evy/pared/releases/latest/download/appcast.xml' "$app_directory/Contents/Info.plist"
updater_public_key=$(cat tools/updater/public-key.txt)
plutil -insert SUPublicEDKey -string "$updater_public_key" "$app_directory/Contents/Info.plist"
plutil -insert SUEnableAutomaticChecks -bool YES "$app_directory/Contents/Info.plist"
plutil -insert SUAutomaticallyUpdate -bool NO "$app_directory/Contents/Info.plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$app_directory/Contents/Info.plist"
plutil -insert SURequireSignedFeed -bool YES "$app_directory/Contents/Info.plist"
codesign --force --sign - "$app_directory"
codesign --verify --deep --strict "$app_directory"
printf 'Built %s\n' "$app_directory"
