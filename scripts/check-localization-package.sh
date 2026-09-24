#!/usr/bin/env bash
# Validate packaging without opening the app or touching installed files.
set -euo pipefail
cd "$(dirname "$0")/.."
bin_dir="${1:-$(swift build --show-bin-path)}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/smart-fan-package.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
bundle=SmartFan_SmartFanLocalization.bundle
# The assembler only copies the icon; a fixture avoids an unrelated icon build.
: > "$check_dir/icon.icns"
"$bin_dir/smart-fan" build-app --binary "$bin_dir/SmartFanApp" --icon "$check_dir/icon.icns" --dest "$check_dir/Check.app"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$check_dir/Check.app/Contents/Info.plist")" = org.witt.smartfan.app
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$check_dir/Check.app/Contents/Info.plist")" = SmartFan
cmp LICENSE "$check_dir/Check.app/Contents/Resources/LICENSE"
resource_dir="$check_dir/Check.app/Contents/Resources/$bundle"
if [ -d "$resource_dir/Contents/Resources" ]; then resource_dir="$resource_dir/Contents/Resources"; fi
for language in en zh-Hans zh-Hant; do
 cmp "Sources/SmartFanLocalization/Resources/$language.json" "$resource_dir/$language.json"
done
mkdir "$check_dir/unbundled"
cp "$bin_dir/SmartFanApp" "$check_dir/unbundled/SmartFanApp"
echo preserve > "$check_dir/Check.app/sentinel"
if "$bin_dir/smart-fan" build-app --binary "$check_dir/unbundled/SmartFanApp" --icon "$check_dir/icon.icns" --dest "$check_dir/Check.app" > "$check_dir/rejection.log" 2>&1; then
 echo "Unexpected success with missing localization resources" >&2
 exit 1
fi
test "$(cat "$check_dir/Check.app/sentinel")" = preserve
printf 'Localization packaging and missing-resource protection passed.\n'
