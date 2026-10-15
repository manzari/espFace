#!/bin/sh
# Renders the widget screenshots of the docs (docs/site/public/widgets) with Playwright against the renderer image.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PW_IMAGE="mcr.microsoft.com/playwright:v1.49.1-noble"
NET=espface-shots
cleanup() { docker rm -f espface-shots-web >/dev/null 2>&1 || true; docker network rm $NET >/dev/null 2>&1 || true; }
cleanup
docker network create $NET >/dev/null
docker build -q --target web -f "$ROOT/server/renderer/Dockerfile" -t espface-renderer-web "$ROOT" >/dev/null
docker run -d --network $NET --name espface-shots-web espface-renderer-web >/dev/null
set +e
docker run --rm --network $NET -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/w -w /w/web \
  -e E2E_BASE=http://espface-shots-web -e ESPFACE_SHOTS=1 \
  "$PW_IMAGE" npx playwright test e2e/widget-shots.spec.ts --workers=4 "$@"
rc=$?
set -e
cleanup
exit $rc
