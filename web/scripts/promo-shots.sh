#!/bin/sh
# Renders the landing page's browser screenshots (promo/images/web-*.jpg) with Playwright against the renderer image.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PW_IMAGE="mcr.microsoft.com/playwright:v$(sed -n 's/.*"@playwright\/test": "[~^]*\([^"]*\)".*/\1/p' "$ROOT/web/package.json")-noble"   # browsers match the test runner
NET=espface-promo
cleanup() { docker rm -f espface-promo-web >/dev/null 2>&1 || true; docker network rm $NET >/dev/null 2>&1 || true; }
cleanup
docker network create $NET >/dev/null
docker build -q --target web -f "$ROOT/server/renderer/Dockerfile" -t espface-renderer-web "$ROOT" >/dev/null
docker run -d --network $NET --name espface-promo-web espface-renderer-web >/dev/null
set +e
docker run --rm --network $NET -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/w -w /w/web \
  -e E2E_BASE=http://espface-promo-web -e ESPFACE_PROMO_SHOTS=1 \
  "$PW_IMAGE" npx playwright test e2e/promo-shots.spec.ts "$@"
rc=$?
set -e
cleanup
exit $rc
