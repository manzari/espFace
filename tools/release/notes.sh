#!/bin/sh
# Prints the CHANGELOG.md section of a version as release notes. Usage: tools/release/notes.sh v1.0.0
set -e
cd "$(dirname "$0")/../.."
v="${1#v}"
awk -v v="$v" 'index($0, "## [" v "]") == 1 {p=1; next} /^## \[/ {p=0} /^\[[^]]+\]: / {p=0} p' CHANGELOG.md > /tmp/espface-notes.$$
grep -q . /tmp/espface-notes.$$ || { echo "no CHANGELOG.md section for $v" >&2; rm -f /tmp/espface-notes.$$; exit 1; }
cat /tmp/espface-notes.$$; rm -f /tmp/espface-notes.$$
