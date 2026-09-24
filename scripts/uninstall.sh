#!/usr/bin/env bash
set -euo pipefail
sudo /usr/local/bin/smart-fan uninstall "$@"
if command -v brew >/dev/null && brew list --formula smart-fan >/dev/null 2>&1; then
    brew uninstall smart-fan
fi
