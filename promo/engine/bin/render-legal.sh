#!/usr/bin/env sh
# Render the legal documents from engrossify v2 into src/_pages/generated/.
#
# Production (CI / Docker build):
#   ENGROSSIFY_URL=https://legal.guestlist.ink \
#   ENGROSSIFY_API_KEY=... \
#     sh bin/render-legal.sh
#
# Local dev:
#   sh bin/render-legal.sh         # writes placeholder pages, no API call
#
# The script ALWAYS rewrites src/_pages/generated/ from scratch so a stale
# render never survives a partial failure.

set -eu

. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

OUT_DIR="src/_pages/generated"

# With a content dir, read straight from it — this lets the Docker build
# render legal docs before the rest of the source is copied, so the layer
# only busts when the tenant config or languages actually change. Without
# one, fall back to the applied tree (local dev after apply-content.sh).
if [ $# -ge 1 ]; then
  CONFIG_PATH="$1/_config.yml"
  YAML_PATH="$1/engrossify.yaml"
else
  CONFIG_PATH="src/_config.yml"
  YAML_PATH="legal/engrossify.yaml"
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.md

# First language is the default (served at "/"); others get "/<lang>/".
LANGUAGES=$(read_flow_list languages "$CONFIG_PATH")
if [ -z "$LANGUAGES" ]; then
  echo "render-legal: could not read languages: from $CONFIG_PATH" >&2
  exit 1
fi
DEFAULT_LANG=$(printf '%s\n' "$LANGUAGES" | head -n1)

# Document list lives in the tenant config — single source of truth.
DOCUMENTS=$(read_flow_list documents "$YAML_PATH")
if [ -z "$DOCUMENTS" ]; then
  echo "render-legal: could not read documents: from $YAML_PATH" >&2
  exit 1
fi

permalink_for() {
  doc="$1"
  lang="$2"
  case "$doc" in
    terms-of-service) base="terms" ;;
    *)                base="$doc" ;;
  esac
  if [ "$lang" = "$DEFAULT_LANG" ]; then
    echo "/$base/"
  else
    echo "/$lang/$base/"
  fi
}

# write_page <doc> <lang> <permalink> <title>  -- reads markdown body from stdin
write_page() {
  out="$OUT_DIR/$1.$2.md"
  # Quote the title for YAML: the API controls it, so escape \ and ".
  esc_title=$(printf '%s' "$4" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  {
    printf -- '---\n'
    printf 'layout: page\n'
    printf 'permalink: %s\n' "$3"
    printf 'hide_page_title: true\n'
    printf 'lang: %s\n' "$2"
    printf 'title: "%s"\n' "$esc_title"
    printf -- '---\n\n'
    cat
  } > "$out"
}

placeholder_title() {
  case "$1.$2" in
    privacy.de)          echo "Datenschutzerklärung" ;;
    privacy.en)          echo "Privacy Policy" ;;
    terms-of-service.de) echo "Allgemeine Geschäftsbedingungen" ;;
    terms-of-service.en) echo "Terms of Service" ;;
    *)                   echo "$1 ($2)" ;;
  esac
}

if [ -z "${ENGROSSIFY_API_KEY:-}" ]; then
  echo "render-legal: ENGROSSIFY_API_KEY unset — writing placeholder pages" >&2
  for doc in $DOCUMENTS; do
    for lang in $LANGUAGES; do
      permalink=$(permalink_for "$doc" "$lang")
      title=$(placeholder_title "$doc" "$lang")
      cat <<EOF | write_page "$doc" "$lang" "$permalink" "$title"
# ${title}

*This page renders at production build time via engrossify.*

Set \`ENGROSSIFY_API_KEY\` to preview the real text.
EOF
    done
  done
  exit 0
fi

: "${ENGROSSIFY_URL:?must be set when ENGROSSIFY_API_KEY is set}"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

status=$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$ENGROSSIFY_URL/api/render" \
  -H "X-Api-Key: $ENGROSSIFY_API_KEY" \
  -H "Content-Type: application/x-yaml" \
  --data-binary "@$YAML_PATH")

if [ "$status" != "200" ]; then
  echo "render-legal: engrossify render failed (HTTP $status):" >&2
  cat "$response_file" >&2
  echo >&2
  exit 1
fi

# Split each document into its own .md file. Each entry travels as one
# base64 line (no field splitting, so empty/odd values can't shift columns).
jq -r '.documents[] | @base64' "$response_file" \
| while read -r row_b64; do
    row=$(printf '%s' "$row_b64" | base64 -d)
    doc=$(printf '%s' "$row" | jq -r '.document')
    lang=$(printf '%s' "$row" | jq -r '.language')
    title=$(printf '%s' "$row" | jq -r '.title // empty')
    [ -n "$title" ] || title=$(placeholder_title "$doc" "$lang")
    permalink=$(permalink_for "$doc" "$lang")
    printf '%s' "$row" | jq -r '.markdown' | write_page "$doc" "$lang" "$permalink" "$title"
  done

count=$(jq '.documents | length' "$response_file")
echo "render-legal: wrote $count document(s) to $OUT_DIR"
