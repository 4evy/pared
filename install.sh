#!/bin/sh
set -eu

fail() {
  printf 'pared bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: sh install.sh [--archive FILE] [wizard arguments...]

Download the latest prebuilt pared release and open its interactive wizard
Requires macOS 27 or later, Apple silicon, and a terminal; do not run as root

  --archive FILE  Use an offline release with FILE.sha256 beside it
  --help          Show this help without downloading

All remaining arguments go unchanged to `pared wizard`, including
--prefix DIR and --policy FILE
USAGE
}

case ${1:-} in
--help | -h)
  usage
  exit 0
  ;;
esac
archive=
if [ "${1:-}" = --archive ]; then
  [ "$#" -ge 2 ] && [ -n "$2" ] || fail '--archive requires a file'
  archive=$2
  shift 2
fi

[ "$(/usr/bin/uname -s)" = Darwin ] || fail 'macOS is required'
[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] ||
  fail 'Apple silicon hardware is required'
version=$(/usr/bin/sw_vers -productVersion)
major=${version%%.*}
case $major in
'' | *[!0-9]*) fail "Cannot determine macOS version: $version" ;;
esac
[ "$major" -ge 27 ] || fail 'macOS 27 or later is required'
[ "$(/usr/bin/id -u)" -ne 0 ] || fail 'Run as your normal user, not root'

# A piped script keeps its script input separate from the wizard's terminal
(
  exec 3<>/dev/tty
  [ -t 3 ]
) 2>/dev/null ||
  fail 'An interactive terminal is required; run this from Terminal'
exec 3<>/dev/tty

umask 077
work=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/pared-bootstrap.XXXXXX")
trap 'rm -rf "$work"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

asset=pared-macos-arm64.tar.gz
if [ -z "$archive" ]; then
  base=https://github.com/4evy/pared/releases/latest/download
  archive=$work/$asset
  printf 'Downloading Pared from GitHub...\n'
  for file in "$asset" "$asset.sha256"; do
    /usr/bin/curl --fail --silent --show-error --location \
      --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --output "$work/$file" "$base/$file" ||
      fail "Cannot download $file; check your connection and release availability"
  done

fi

[ -f "$archive" ] || fail "Archive not found: $archive"
[ -f "$archive.sha256" ] || fail "Checksum file not found: $archive.sha256"
# Accept exactly one shasum-format record for the expected release filename
exec 4<"$archive.sha256"
IFS= read -r checksum <&4 || fail 'Invalid release checksum record'
extra=
if IFS= read -r extra <&4 || [ -n "$extra" ]; then
  fail 'The release checksum must contain exactly one record'
fi
exec 4<&-
expected=${checksum%% *}
[ "$checksum" = "$expected  $asset" ] && [ "${#expected}" -eq 64 ] ||
  fail 'Invalid release checksum filename or hash'
case $expected in
*[!0123456789abcdefABCDEF]*) fail 'Invalid SHA-256 release hash' ;;
esac
actual=$(/usr/bin/shasum -a 256 "$archive")
actual=${actual%% *}
expected=$(printf '%s' "$expected" | /usr/bin/tr 'ABCDEF' 'abcdef')
[ "$actual" = "$expected" ] || fail 'Release archive checksum mismatch'
/usr/bin/tar -tzf "$archive" >"$work/entries" || fail 'Cannot read release archive'
while IFS= read -r entry; do
  case $entry in
  pared | pared_Pared.bundle | pared_Pared.bundle/) ;;
  pared_Pared.bundle/*)
    case $entry in
    */../* | */./* | *//* | */.. | */.) fail "Unsafe archive path: $entry" ;;
    esac
    ;;
  *) fail "Unexpected archive entry: $entry" ;;
  esac
done <"$work/entries"

# Extract only the executable and its sibling SwiftPM resource bundle
/usr/bin/tar -xzf "$archive" -C "$work" --no-same-owner \
  pared pared_Pared.bundle || fail 'Cannot extract release payload'
[ -f "$work/pared" ] && [ -x "$work/pared" ] && [ ! -L "$work/pared" ] ||
  fail 'The archive must contain a real executable named pared'
[ -d "$work/pared_Pared.bundle" ] && [ ! -L "$work/pared_Pared.bundle" ] ||
  fail 'The archive must contain a real pared_Pared.bundle directory'

# Keep the payload alive until the wizard returns, including cancellation
if "$work/pared" wizard "$@" <&3 >&3 2>&3; then
  exit 0
else
  exit "$?"
fi
