#!/bin/sh
set -eu

# Build a Finder-launchable app while retaining the same CLI executable
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in
debug | release) ;;
*)
	printf 'Usage: tools/build-app.sh [debug|release]\n' >&2
	exit 64
	;;
esac
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
app_directory="$(pwd)/.build/Pared.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/pared" "$app_directory/Contents/MacOS/.pared-new"
mv -f "$app_directory/Contents/MacOS/.pared-new" "$app_directory/Contents/MacOS/pared"
# SwiftPM finds Bundle.module resources inside the app's Resources directory
for resources in "$binary_directory"/*.bundle; do
	[ -d "$resources" ] || continue
	destination="$app_directory/Contents/Resources/$(basename "$resources")"
	rm -rf "$destination"
	cp -R "$resources" "$destination"
done
swift tools/app-icon.swift .build/Pared.iconset
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
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app_directory"
printf 'Built %s\n' "$app_directory"
