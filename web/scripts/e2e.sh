#!/bin/sh
# Playwright smoke test in Docker: fake device + nginx renderer (built from source) + Playwright on one network.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PW_IMAGE="mcr.microsoft.com/playwright:v1.49.1-noble"
NET=espface-e2e
cleanup() { docker rm -f espface-e2e-fake espface-e2e-web >/dev/null 2>&1 || true; docker network rm $NET >/dev/null 2>&1 || true; }
cleanup
docker network create $NET >/dev/null
docker build -q -f "$ROOT/docker/fake-device.Dockerfile" -t espface-fake "$ROOT" >/dev/null
docker build -q -f "$ROOT/server/renderer/Dockerfile" -t espface-renderer "$ROOT" >/dev/null
docker run -d --network $NET --name espface-e2e-fake espface-fake --pin=1234 >/dev/null
docker run -d --network $NET --name espface-e2e-web espface-renderer >/dev/null
set +e
docker run --rm --network $NET -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/w -w /w/web \
  -e E2E_BASE=http://espface-e2e-web -e E2E_DEVICE=espface-e2e-fake:8080 "$PW_IMAGE" npx playwright test "$@"
rc=$?
set -e
cleanup
exit $rc
