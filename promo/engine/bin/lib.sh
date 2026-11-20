#!/usr/bin/env sh
# Shared YAML readers for the build scripts. Deliberately awk-only: the
# builder image has no Ruby YAML on PATH before `bundle exec`, and these
# read a handful of well-known keys, not arbitrary YAML.

# read_flow_list <key> <file> — parse a flow-style `key: [a, b, c]` list,
# one element per line.
read_flow_list() {
  awk -v key="$1" '
    $0 ~ "^" key ":[[:space:]]*\\[" {
      line=$0
      sub(/^[^[]*\[/, "", line)
      sub(/\].*$/, "", line)
      gsub(/[[:space:]]/, "", line)
      n=split(line, parts, ",")
      for (i=1; i<=n; i++) if (parts[i] != "") print parts[i]
      exit
    }
  ' "$2"
}

# read_nested <parent> <child> <file> — read a one-level-nested scalar, e.g.
#   not_found:
#     title: "Page Not Found"
# Returns the value with surrounding quotes stripped.
read_nested() {
  awk -v parent="$1" -v child="$2" '
    $0 ~ "^" parent ":[[:space:]]*$" { inside=1; next }
    inside && /^[^[:space:]#]/ { inside=0 }
    inside && $0 ~ "^[[:space:]]+" child ":" {
      sub("^[[:space:]]+" child ":[[:space:]]*", "")
      sub(/[[:space:]]+$/, "")
      gsub(/^"|"$/, "")
      gsub(/^'\''|'\''$/, "")
      print
      exit
    }
  ' "$3"
}
