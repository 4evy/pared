#!/bin/sh
set -eu

# Run from the repository root; developer tools are only needed to make releases
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || {
	printf 'Release packaging requires an Apple silicon Mac.\n' >&2
	exit 1
}
output=${1:-dist}
mkdir -p "$output"
output=$(cd "$output" && pwd)
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
sh tools/build-app.sh release
codesign --verify --deep --strict .build/Pared.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
	.build/Pared.app "$output/pared-app-macos-arm64.zip"
(
	cd "$output"
	shasum -a 256 pared-macos-arm64.tar.gz >pared-macos-arm64.tar.gz.sha256
	shasum -a 256 pared-app-macos-arm64.zip >pared-app-macos-arm64.zip.sha256
)
cp install.sh "$output/install.sh"
printf '\nRelease files are ready in %s\n' "$output"
