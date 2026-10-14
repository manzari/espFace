#!/bin/sh
# Checks that all release versions agree, contain no digit 4 and match the tag (v<version>) when one is given.
# Usage: tools/release/check-versions.sh [tag]    e.g. tools/release/check-versions.sh v1.0.0
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
pkg() { sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$1" | head -1; }
LP=$(sed -n 's/^version=//p' firmware/library.properties)
LJ=$(pkg firmware/library.json)
PH=$(sed -n 's/^#define ESPFACE_LIB_VERSION "\([^"]*\)".*/\1/p' firmware/src/core/Platform.h)
WEB=$(pkg web/package.json)
FAKE=$(pkg tools/fake-device/package.json)
DOCS=$(pkg docs/site/package.json)
status=0
printf '%-36s %s\n' firmware/library.properties "$LP" firmware/library.json "$LJ" "Platform.h ESPFACE_LIB_VERSION" "$PH" \
  web/package.json "$WEB" tools/fake-device/package.json "$FAKE" docs/site/package.json "$DOCS"
for v in "$LJ" "$PH" "$WEB" "$FAKE" "$DOCS"; do
  [ "$v" = "$LP" ] || { echo "version mismatch: '$v' != library.properties '$LP'" >&2; status=1; }
done
echo "$LP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "not a plain semver: $LP" >&2; status=1; }
case "$LP" in *4*) echo "version $LP contains the digit 4" >&2; status=1 ;; esac
if [ -n "$1" ]; then
  case "$1" in *4*) echo "tag $1 contains the digit 4" >&2; status=1 ;; esac
  [ "$1" = "v$LP" ] || { echo "tag $1 does not match version v$LP" >&2; status=1; }
fi
[ $status = 0 ] && echo "versions OK: $LP${1:+ (tag $1)}"
exit $status
