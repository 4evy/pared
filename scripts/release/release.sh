#!/usr/bin/env bash
set -eu

# Run from the repository root; developer tools are only needed to make releases
host_system=$(uname -s)
host_architecture=$(uname -m)
[ "$host_system" = Darwin ] && [ "$host_architecture" = arm64 ] || {
	printf 'Release packaging requires an Apple silicon Mac.\n' >&2
	exit 1
}
output=${1:-dist}
mkdir -p "$output"
output=$(cd "$output" && pwd)
repository_version="$(cat VERSION)"
version="${RELEASE_TAG:-$repository_version}"
printf '%s\n' "$version" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ { valid = 1 } END { exit !valid }' || {
	printf 'Release version must have the form MAJOR.MINOR.PATCH\n' >&2
	exit 1
}
[ "$version" = "$repository_version" ] || {
	printf 'Release tag must match VERSION (%s)\n' "$repository_version" >&2
	exit 1
}
if [ "${CI:-}" = true ] && [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
	printf 'Configure the SPARKLE_PRIVATE_KEY Actions secret before releasing.\n' >&2
	exit 1
fi
# Require curated notes before spending time building or signing a release
swift scripts/release/notes.swift "$version" >"$output/release-notes.md"
stage=$(mktemp -d "${TMPDIR:-/tmp}/pared-release.XXXXXX")
trap 'rm -rf "$stage"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

swift build --configuration release --force-resolved-versions
build=$(swift build --configuration release --force-resolved-versions --show-bin-path)
cp "$build/pared" "$stage/pared"
cp -R "$build/pared_Pared.bundle" "$stage/pared_Pared.bundle"
# Ad-hoc signing needs no Apple account and does not imply notarization
codesign --force --sign - "$stage/pared"

tar -czf "$output/pared-macos-arm64.tar.gz" -C "$stage" pared pared_Pared.bundle
# Keep the Finder app separate from the terminal bootstrap's payload
sh tools/app/app.sh release
sparkle_tools="$(pwd)/App/.build/artifacts/sparkle/Sparkle/bin"
codesign --verify --deep --strict .build/Pared.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
	.build/Pared.app "$output/pared-app-macos-arm64.zip"
mkdir -p "$stage/updates"
cp "$output/pared-app-macos-arm64.zip" "$stage/updates/"
cp "$output/release-notes.md" "$stage/updates/pared-app-macos-arm64.md"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
	# Feed the CI secret through stdin, never through command arguments or a file
	printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_tools/generate_appcast" \
		--ed-key-file - --embed-release-notes --maximum-deltas 0 \
		--download-url-prefix "https://github.com/4evy/pared/releases/download/$version/" \
		--link https://github.com/4evy/pared/releases \
		"$stage/updates"
else
	"$sparkle_tools/generate_appcast" --account org.pared.app \
		--embed-release-notes --maximum-deltas 0 \
		--download-url-prefix "https://github.com/4evy/pared/releases/download/$version/" \
		--link https://github.com/4evy/pared/releases \
		"$stage/updates"
fi
cp "$stage/updates/appcast.xml" "$output/appcast.xml"
(
	cd "$output"
	shasum -a 256 pared-macos-arm64.tar.gz >pared-macos-arm64.tar.gz.sha256
	shasum -a 256 pared-app-macos-arm64.zip >pared-app-macos-arm64.zip.sha256
)
cp install.sh "$output/install.sh"
printf '\nRelease files are ready in %s\n' "$output"
