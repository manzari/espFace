#!/bin/sh
# Builds the baseline sketch and every example for the given boards with pio ci; writes footprint.md with deltas.
# An example may ship a build_flags file (e.g. EmbeddedWeb: -DESPFACE_EMBED_WEB) that is appended to the build flags.
# Usage: tools/ci-build.sh [board ...]   (default: esp32dev esp32-s3-devkitc-1)
set -e
cd "$(dirname "$0")/.."
BOARDS="${*:-esp32dev esp32-s3-devkitc-1}"
OUT=footprint.md
build() { # $1 ino, $2 board, $3 extra flags -> prints "ram flash"
  log=$(mktemp)
  pio ci --lib . --board "$2" --project-option="lib_deps=bblanchon/ArduinoJson@^7.2.0" --project-option="build_flags=-DCORE_DEBUG_LEVEL=0 $3" "$1" > "$log" 2>&1 \
    || { echo "build failed: $1 $2" >&2; grep -E "error|Error" "$log" | head -40 >&2; exit 1; }
  ram=$(grep -oE 'RAM:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
  flash=$(grep -oE 'Flash:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
  rm -f "$log"
  echo "$ram $flash"
}
echo "| Example | Board | RAM static (bytes) | Flash (bytes) | RAM delta vs baseline | Flash delta vs baseline |" > "$OUT"
echo "|---|---|---|---|---|---|" >> "$OUT"
for board in $BOARDS; do
  set -- $(build test/baseline/baseline.ino "$board" ""); bram=$1; bflash=$2
  echo "| baseline (WiFi+httpd+mDNS+DNS+NVS) | $board | $bram | $bflash | 0 | 0 |" >> "$OUT"
  for ex in examples/*/; do
    name=$(basename "$ex")
    flags=""; [ -f "$ex/build_flags" ] && flags=$(cat "$ex/build_flags")
    set -- $(build "$ex$name.ino" "$board" "$flags"); ram=$1; flash=$2
    echo "| $name | $board | $ram | $flash | $((ram - bram)) | $((flash - bflash)) |" >> "$OUT"
  done
done
cat "$OUT"
