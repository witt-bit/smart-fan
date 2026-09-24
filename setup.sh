#!/bin/bash
# Build a complete app before replacing any running installation.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
if [ ! -f SmartFan.icns ]; then
    swift Scripts/generate-icon.swift
    iconutil -c icns SmartFan.iconset -o SmartFan.icns
fi
"$bin_dir/smart-fan" build-app --binary "$bin_dir/SmartFanApp" \
    --icon SmartFan.icns --dest "$bin_dir/SmartFan.app"
codesign --force --deep --sign - "$bin_dir/SmartFan.app"
sudo "$bin_dir/smart-fan" install "$@"
open /Applications/SmartFan.app
