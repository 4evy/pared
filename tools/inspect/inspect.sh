#!/usr/bin/env bash
set -eu

# Keep diagnostics isolated from SwiftPM's product builds
repository="$(cd "$(dirname "$0")/../.." && pwd)"
build_directory="$(mktemp -d "${TMPDIR:-/tmp}/pared-inspect.XXXXXX")"
trap 'rm -rf "$build_directory"' EXIT
xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library -O -g \
  "$repository"/Sources/AssetBridge/*.swift "$repository/tools/inspect/inspect.swift" \
  -o "$build_directory/inspect-uaf"
"$build_directory/inspect-uaf" "$@"
