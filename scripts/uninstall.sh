#!/usr/bin/env bash
set -euo pipefail
# The daemon binary is its own helper (no CLI is exposed on PATH).
sudo /Library/PrivilegedHelperTools/org.witt.smartfan.helper uninstall "$@"
if command -v brew >/dev/null && brew list --cask smart-fan >/dev/null 2>&1; then
    brew uninstall --cask smart-fan
fi
