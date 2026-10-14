#!/bin/sh
# Builds the baseline sketch and every example for the given boards with pio ci; writes footprint.md (one table per
# board) with deltas against the baseline. Per example: build_flags (appended), lib_deps (extra libraries), boards
# (the only boards it builds for), project_options (extra platformio.ini options, one per line). Per board:
# tools/boards/<board>.flags (e.g. USB CDC on S2/S3/C3/C6), <board>.options (extra platformio.ini options) and
# <board>.platform (a platform spec for boards the stock platformio/espressif32 cannot build: ESP32-C6 on pioarduino).
# Usage: tools/ci-build.sh [board ...]   (default: esp32dev esp32-s3-devkitc-1 esp32-s2-saola-1 esp32-c3-devkitm-1 esp32-c6-devkitc-1)
# Env: FOOTPRINT_OUT (default footprint.md), ALLOW_FAIL="board ..." (a failing build of these boards is reported, not fatal)
set -e
cd "$(dirname "$0")/.."
BOARDS="${*:-esp32dev esp32-s3-devkitc-1 esp32-s2-saola-1 esp32-c3-devkitm-1 esp32-c6-devkitc-1}"
OUT="${FOOTPRINT_OUT:-footprint.md}"
status=0
build() { # $1 ino, $2 board, $3 extra flags, $4 extra lib_deps, $5 project_options file or "" -> prints "ram flash" or "fail"
  log=$(mktemp); ino=$1; board=$2; flags=$3; optfile=$5
  ld="bblanchon/ArduinoJson@^7.2.0"; [ -n "$4" ] && ld="$ld, $4"
  set --
  [ -f "tools/boards/$board.platform" ] && set -- "$@" --project-option="platform=$(cat "tools/boards/$board.platform")"
  [ -f "tools/boards/$board.flags" ] && flags="$(cat "tools/boards/$board.flags") $flags"
  [ -f "tools/boards/$board.options" ] && while read -r o; do [ -n "$o" ] && set -- "$@" --project-option="$o"; done < "tools/boards/$board.options"
  [ -n "$optfile" ] && while read -r o; do [ -n "$o" ] && set -- "$@" --project-option="$o"; done < "$optfile"
  if pio ci --lib . --board "$board" --project-option="lib_deps=$ld" --project-option="build_flags=-DCORE_DEBUG_LEVEL=0 $flags" "$@" "$ino" > "$log" 2>&1; then
    ram=$(grep -oE 'RAM:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
    flash=$(grep -oE 'Flash:.*used +[0-9]+ bytes' "$log" | grep -oE '[0-9]+ bytes' | head -1 | grep -oE '[0-9]+')
    rm -f "$log"; echo "$ram $flash"
  else
    echo "build failed: $ino $board" >&2; grep -E "error|Error" "$log" | head -40 >&2; rm -f "$log"; echo "fail"
  fi
}
: > "$OUT"
for board in $BOARDS; do
  allow=0; for b in $ALLOW_FAIL; do [ "$b" = "$board" ] && allow=1; done
  platform="platformio/espressif32"; [ -f "tools/boards/$board.platform" ] && platform=$(cat "tools/boards/$board.platform")
  echo "## $board" >> "$OUT"
  echo "" >> "$OUT"
  echo "Platform: \`$platform\`$( [ -f "tools/boards/$board.flags" ] && printf ', board flags: `%s`' "$(cat "tools/boards/$board.flags")")$( [ -f "tools/boards/$board.options" ] && printf ', options: `%s`' "$(tr '\n' ' ' < "tools/boards/$board.options" | sed 's/ *$//')")" >> "$OUT"
  echo "" >> "$OUT"
  echo "| Example | RAM static (bytes) | Flash (bytes) | RAM delta vs baseline | Flash delta vs baseline |" >> "$OUT"
  echo "|---|---|---|---|---|" >> "$OUT"
  set -- $(build test/baseline/baseline.ino "$board" "" "" "")
  if [ "$1" = "fail" ]; then
    echo "| baseline | build failed | | | |" >> "$OUT"; echo "" >> "$OUT"
    [ $allow = 1 ] || status=1; continue
  fi
  bram=$1; bflash=$2
  echo "| baseline (WiFi+httpd+mDNS+DNS+NVS) | $bram | $bflash | 0 | 0 |" >> "$OUT"
  for ex in examples/*/; do
    name=$(basename "$ex")
    if [ -f "$ex/boards" ] && ! grep -qx "$board" "$ex/boards"; then continue; fi
    flags=""; [ -f "$ex/build_flags" ] && flags=$(cat "$ex/build_flags")
    deps=""; [ -f "$ex/lib_deps" ] && deps=$(cat "$ex/lib_deps")
    opts=""; [ -f "$ex/project_options" ] && opts="$ex/project_options"
    set -- $(build "$ex$name.ino" "$board" "$flags" "$deps" "$opts")
    if [ "$1" = "fail" ]; then echo "| $name | build failed | | | |" >> "$OUT"; [ $allow = 1 ] || status=1; continue; fi
    ram=$1; flash=$2
    echo "| $name | $ram | $flash | $((ram - bram)) | $((flash - bflash)) |" >> "$OUT"
  done
  echo "" >> "$OUT"
done
cat "$OUT"
exit $status
