#!/bin/sh
# Fails when the Minimal flash delta on esp32dev in footprint.md exceeds the budget (bytes) in footprint.budget.
# Usage: tools/footprint-check.sh [footprint.md] [footprint.budget]
set -e
cd "$(dirname "$0")/.."
md="${1:-footprint.md}"; budget=$(grep -oE '^[0-9]+' "${2:-footprint.budget}" | head -1)
delta=$(awk '/^## esp32dev$/{s=1;next} /^## /{s=0} s && $2=="Minimal"{print $6}' FS='[ |]+' "$md" | head -1)
[ -n "$delta" ] || { echo "no Minimal/esp32dev row in $md" >&2; exit 1; }
echo "Minimal flash delta on esp32dev: $delta bytes (budget $budget)"
[ "$delta" -le "$budget" ] || { echo "footprint budget exceeded" >&2; exit 1; }
