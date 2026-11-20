#!/usr/bin/env sh
# Merge a project's content into the engine's src/ tree, ready for Jekyll.
#
#   sh bin/apply-content.sh content/bruchbuch
#
# Everything this writes is generated and gitignored. It is safe to re-run:
# generated paths are cleared first, so switching between content dirs never
# leaves a stale image or language page behind.
#
# A content directory holds exactly what a project repo ships:
#   _config.yml       project settings (merged onto config/engine.yml)
#   engrossify.yaml   tenant config for the legal render
#   i18n/<lang>.yml   all translatable strings
#   images/           screenshots + favicon
#   brand.css         optional per-project style overrides
#   assetlinks.json   optional Android Digital Asset Links statement list

set -eu

SRC_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$SRC_DIR/bin/lib.sh"

CONTENT="${1:-}"
if [ -z "$CONTENT" ]; then
  echo "usage: sh bin/apply-content.sh <content-dir>" >&2
  exit 1
fi
if [ ! -d "$CONTENT" ]; then
  echo "apply-content: no such content directory: $CONTENT" >&2
  exit 1
fi
for required in _config.yml engrossify.yaml i18n; do
  if [ ! -e "$CONTENT/$required" ]; then
    echo "apply-content: $CONTENT is missing $required" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Config: engine defaults + project settings -> src/_config.yml
# ---------------------------------------------------------------------------
{
  cat config/engine.yml
  echo
  cat "$CONTENT/_config.yml"
} > src/_config.yml

LANGUAGES=$(read_flow_list languages src/_config.yml)
if [ -z "$LANGUAGES" ]; then
  echo "apply-content: $CONTENT/_config.yml declares no languages:" >&2
  exit 1
fi
DEFAULT_LANG=$(printf '%s\n' "$LANGUAGES" | head -n1)

# ---------------------------------------------------------------------------
# Translations, images, brand overrides, legal tenant config
# ---------------------------------------------------------------------------
rm -rf src/_data/i18n src/assets/images
mkdir -p src/_data/i18n src/assets/images legal
cp "$CONTENT"/i18n/*.yml src/_data/i18n/

for lang in $LANGUAGES; do
  if [ ! -f "src/_data/i18n/$lang.yml" ]; then
    echo "apply-content: languages: lists '$lang' but $CONTENT/i18n/$lang.yml is missing" >&2
    exit 1
  fi
done

if [ -d "$CONTENT/images" ]; then
  find "$CONTENT/images" -type f -exec cp {} src/assets/images/ \;
fi

cp "$CONTENT/engrossify.yaml" legal/engrossify.yaml

# Always present so head.html can link it unconditionally; empty when the
# project has no overrides.
if [ -f "$CONTENT/brand.css" ]; then
  cp "$CONTENT/brand.css" src/assets/css/brand.css
else
  : > src/assets/css/brand.css
fi

# Optional Digital Asset Links, served at /.well-known/assetlinks.json.
# Copied verbatim: the verifier is strict about key names and formatting.
rm -f src/.well-known/assetlinks.json
rmdir src/.well-known 2>/dev/null || true
if [ -f "$CONTENT/assetlinks.json" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "apply-content: jq is required to validate $CONTENT/assetlinks.json" >&2
    exit 1
  fi
  if ! problems=$(jq -rs -f "$SRC_DIR/bin/check-assetlinks.jq" "$CONTENT/assetlinks.json" 2>&1) \
     || [ -n "$problems" ]; then
    echo "apply-content: invalid $CONTENT/assetlinks.json:" >&2
    printf '%s\n' "$problems" | sed 's/^/  /' >&2
    exit 1
  fi
  mkdir -p src/.well-known
  cp "$CONTENT/assetlinks.json" src/.well-known/assetlinks.json
fi

# ---------------------------------------------------------------------------
# Per-language entry pages. Pure boilerplate driven by languages:, so the
# engine generates them instead of every project carrying copies.
# ---------------------------------------------------------------------------

# Clear language dirs left by an earlier apply — a previous content dir may
# have had languages this one doesn't, and a stale src/en/index.html would
# otherwise still be built and served. Only ever touches generated filenames.
for dir in src/*/; do
  case "$dir" in
    src/_*/ | src/assets/) continue ;;
  esac
  rm -f "$dir/index.html" "$dir/404.html"
  rmdir "$dir" 2>/dev/null || true
done

for lang in $LANGUAGES; do
  if [ "$lang" = "$DEFAULT_LANG" ]; then
    dir="src"
    root="/"
  else
    dir="src/$lang"
    root="/$lang/"
    rm -rf "$dir"
    mkdir -p "$dir"
  fi

  cat > "$dir/index.html" <<EOF
---
layout: default
lang: $lang
permalink: $root
---

{% include landing.html %}
EOF

  nf_title=$(read_nested not_found title "src/_data/i18n/$lang.yml")
  [ -n "$nf_title" ] || nf_title="Page Not Found"
  esc_title=$(printf '%s' "$nf_title" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

  cat > "$dir/404.html" <<EOF
---
layout: page
title: "$esc_title"
permalink: ${root}404.html
lang: $lang
hide_page_title: true
lang_alt_root: true
---

{% include not_found.html %}
EOF
done

# ---------------------------------------------------------------------------
# nginx: one 404 mapping per non-default language
# ---------------------------------------------------------------------------
lang_locations=""
lang_internals=""
for lang in $LANGUAGES; do
  [ "$lang" = "$DEFAULT_LANG" ] && continue
  lang_locations="${lang_locations}    location /$lang/ {
        error_page 404 /$lang/404.html;
        try_files \$uri \$uri/ \$uri.html =404;
    }

"
  lang_internals="${lang_internals}    location = /$lang/404.html {
        internal;
    }
"
done

awk -v locations="$lang_locations" -v internals="$lang_internals" '
  /@@LANG_LOCATIONS@@/ { printf "%s", locations; next }
  /@@LANG_404_INTERNAL@@/ { printf "%s", internals; next }
  { print }
' nginx.conf.template > nginx.conf

echo "apply-content: applied $CONTENT (languages: $(echo $LANGUAGES | tr '\n' ' '))"
