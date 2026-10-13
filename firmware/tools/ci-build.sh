#!/bin/sh
# Builds the baseline sketch and every example for the given boards with pio ci; writes footprint.md with deltas.
# An example may ship a build_flags file (e.g. EmbeddedWeb: -DESPFACE_EMBED_WEB) that is appended to the build flags,
# a lib_deps file with extra libraries (BleOnly: NimBLE-Arduino), a boards file listing the only boards it builds for
# and a project_options file with extra platformio.ini options, one per line (BtClassic: a larger app partition).
# Usage: tools/ci-build.sh [board ...]   (default: esp32dev esp32-s3-devkitc-1)
set -e
cd "$(dirname "$0")/.."
BOARDS="${*:-esp32dev esp32-s3-devkitc-1}"
OUT=footprint.md
build() { # $1 ino, $2 board, $3 extra flags, $4 extra lib_deps, $5 project_options file or "" -> prints "ram flash"
  log=$(mktemp); ino=$1; board=$2; flags=$3; optfile=$5
  ld="bblanchon/ArduinoJson@^7.2.0"; [ -n "$4" ] && ld="$ld, $4"
  set --
  [ -n "$optfile" ] && while read -r o; do [ -n "$o" ] && set -- "$@" --project-option="$o"; done < "$optfile"
  pio ci --lib . --board "$board" --project-option="lib_deps=$ld" --project-option="build_flags=-DCORE_DEBUG_LEVEL=0 $flags" "$@" "$ino" > "$log" 2>&1 \
    || { echo "build failed: $ino $board" >&2; grep -E "error|Error" "$log" | head -40 >&2; exit 1; }
  ram=$(grep -oE 'RAM:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
  flash=$(grep -oE 'Flash:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
  rm -f "$log"
  echo "$ram $flash"
}
echo "| Example | Board | RAM static (bytes) | Flash (bytes) | RAM delta vs baseline | Flash delta vs baseline |" > "$OUT"
echo "|---|---|---|---|---|---|" >> "$OUT"
for board in $BOARDS; do
  set -- $(build test/baseline/baseline.ino "$board" "" "" ""); bram=$1; bflash=$2
  echo "| baseline (WiFi+httpd+mDNS+DNS+NVS) | $board | $bram | $bflash | 0 | 0 |" >> "$OUT"
  for ex in examples/*/; do
    name=$(basename "$ex")
    if [ -f "$ex/boards" ] && ! grep -qx "$board" "$ex/boards"; then continue; fi
    flags=""; [ -f "$ex/build_flags" ] && flags=$(cat "$ex/build_flags")
    deps=""; [ -f "$ex/lib_deps" ] && deps=$(cat "$ex/lib_deps")
    opts=""; [ -f "$ex/project_options" ] && opts="$ex/project_options"
    set -- $(build "$ex$name.ino" "$board" "$flags" "$deps" "$opts"); ram=$1; flash=$2
    echo "| $name | $board | $ram | $flash | $((ram - bram)) | $((flash - bflash)) |" >> "$OUT"
  done
done
cat "$OUT"
