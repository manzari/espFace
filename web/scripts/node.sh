#!/bin/sh
# Runs a command in node:22-alpine with the repository mounted at /w and web/ as cwd. Usage: scripts/node.sh npm ci
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/w -w /w/web ${DOCKER_ARGS:-} node:22-alpine "$@"
