#!/usr/bin/env bash
# Produce the same signed app + CLI layout used by Homebrew and source installs.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
version="$("$bin_dir/smart-fan" --version)"
architecture="$(uname -m)"
test "$architecture" = arm64
if [ -n "${RELEASE_TAG:-}" ]; then test "$RELEASE_TAG" = "v$version"; fi
output_dir="${1:-$PWD/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/smart-fan-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
name="SmartFan-$version-macos-$architecture"
mkdir -p "$stage/$name/bin"
cp "$bin_dir/smart-fan" "$stage/$name/bin/smart-fan"
"$bin_dir/smart-fan" build-app --binary "$bin_dir/SmartFanApp" --cli "$bin_dir/smart-fan" \
    --icon SmartFan.icns --dest "$stage/$name/SmartFan.app"
cp LICENSE NOTICE.md README.md "$stage/$name/"
cp -R ThirdPartyNotices "$stage/$name/"
codesign --force --deep --sign - "$stage/$name/SmartFan.app"
codesign --verify --deep --strict "$stage/$name/SmartFan.app"
COPYFILE_DISABLE=1 tar -czf "$output_dir/$name.tar.gz" -C "$stage" "$name"
(cd "$output_dir" && shasum -a 256 "$name.tar.gz" > SHA256SUMS)
printf 'Packaged %s\n' "$output_dir/$name.tar.gz"
