#!/usr/bin/env bash
set -eu

# Replay the README demo with a disposable policy and no preference writes
cd "$(dirname "$0")/.."
command -v vhs >/dev/null
command -v ffmpeg >/dev/null
command -v cwebp >/dev/null
swift build
PARED_DEMO_BIN="$(swift build --show-bin-path)"
export PARED_DEMO_BIN
demo_directory="$(mktemp -d "${TMPDIR:-/tmp}/pared-demo.XXXXXX")"
trap 'rm -rf "$demo_directory"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
PARED_DEMO_POLICY="$demo_directory/policy.json"
export PARED_DEMO_POLICY
printf '%s\n' '{"schemaVersion":1,"defaultState":"disabled","features":{}}' >"$PARED_DEMO_POLICY"
vhs .github/assets/wizard.tape
ffmpeg -hide_banner -loglevel error -y -i .github/assets/wizard.gif \
	-c:v libvpx-vp9 -b:v 0 -crf 24 -pix_fmt yuv420p \
	docs/site/public/images/wizard.webm
ffmpeg -hide_banner -loglevel error -y -ss 8 -i .github/assets/wizard.gif \
	-frames:v 1 "$demo_directory/wizard.png"
cwebp -quiet -lossless "$demo_directory/wizard.png" \
	-o docs/site/public/images/wizard.webp
