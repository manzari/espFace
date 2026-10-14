#!/bin/sh
# Builds the standalone Arduino library tree (library.properties at the root) from firmware/ for Library Manager.
# Usage: tools/release/split-library.sh export [dir]   copy the library into dir (default build/release/espFace)
#        tools/release/split-library.sh zip            export + build/release/espFace-<version>.zip (top folder espFace/)
#        tools/release/split-library.sh push           export, commit and tag v<version> in a clone of ESPFACE_LIB_REMOTE
# Env (push): ESPFACE_LIB_REMOTE  library repo URL, e.g. https://git.hauptstadt.monster/manzari/espFace-arduino.git
#             ESPFACE_LIB_BRANCH  branch (default main); ESPFACE_PUSH=1 really pushes, otherwise the push is only printed
#             ESPFACE_MIRROR_URL  public mirror of that repo (the URL submitted to the Library Manager), only printed
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FW="$ROOT/firmware"
OUT="$ROOT/build/release"
FILES="src examples library.properties library.json README.md LICENSE CHANGELOG.md"
VER=$(sed -n 's/^version=//p' "$FW/library.properties")
GIT=${GIT:-git}

export_tree() { # $1 target dir
  rm -rf "$1"; mkdir -p "$1"
  for f in $FILES; do cp -R "$FW/$f" "$1/"; done
  bad=$(find "$1" -type l -o -name '*.exe' -o -name '.development' -o -name '.pio' -o -name 'test_output')
  [ -z "$bad" ] || { echo "not allowed in a Library Manager release: $bad" >&2; exit 1; }
  echo "exported espFace $VER to $1" >&2
}

case "${1:-export}" in
  export) export_tree "${2:-$OUT/espFace}" ;;
  zip)
    export_tree "$OUT/espFace"
    rm -f "$OUT/espFace-$VER.zip"
    (cd "$OUT" && zip -qrX "espFace-$VER.zip" espFace)
    echo "$OUT/espFace-$VER.zip" ;;
  push)
    : "${ESPFACE_LIB_REMOTE:?set ESPFACE_LIB_REMOTE to the library repo URL}"
    case "$VER" in *4*) echo "version $VER contains the digit 4, refusing" >&2; exit 1 ;; esac
    BR=${ESPFACE_LIB_BRANCH:-main}
    SRC=$($GIT -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
    WORK="$OUT/espFace-repo"; rm -rf "$WORK"
    if ! $GIT clone -q --branch "$BR" "$ESPFACE_LIB_REMOTE" "$WORK" 2>/dev/null; then
      rm -rf "$WORK"; $GIT init -q -b "$BR" "$WORK"; $GIT -C "$WORK" remote add origin "$ESPFACE_LIB_REMOTE"
    fi
    if $GIT -C "$WORK" rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then echo "tag v$VER already exists" >&2; exit 1; fi
    find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    export_tree "$OUT/espFace"; cp -R "$OUT/espFace/." "$WORK/"
    $GIT -C "$WORK" add -A
    $GIT -C "$WORK" -c user.name="${GIT_AUTHOR_NAME:-espFace release}" -c user.email="${GIT_AUTHOR_EMAIL:-release@espface.invalid}" \
      commit -q --allow-empty -m "espFace $VER (from monorepo $SRC)"
    $GIT -C "$WORK" -c user.name="${GIT_AUTHOR_NAME:-espFace release}" -c user.email="${GIT_AUTHOR_EMAIL:-release@espface.invalid}" \
      tag -a "v$VER" -m "espFace $VER"
    if [ "${ESPFACE_PUSH:-0}" = 1 ]; then $GIT -C "$WORK" push origin "$BR" "v$VER"
    else echo "dry run; to publish: $GIT -C $WORK push origin $BR v$VER   (or rerun with ESPFACE_PUSH=1)"; fi
    [ -n "$ESPFACE_MIRROR_URL" ] && echo "Library Manager URL (after the push mirror syncs): $ESPFACE_MIRROR_URL"
    exit 0 ;;
  *) echo "usage: $0 export [dir] | zip | push" >&2; exit 2 ;;
esac
