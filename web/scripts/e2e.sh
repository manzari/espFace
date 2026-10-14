#!/bin/sh
# Playwright tests in Docker: fake devices (plain + hardening knobs) + nginx renderer (built from source) + Playwright on one network.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PW_IMAGE="mcr.microsoft.com/playwright:v1.49.1-noble"
NET=espface-e2e
NAMES="fake drop slow huge busy flaky lock web"
cleanup() { for n in $NAMES; do docker rm -f espface-e2e-$n >/dev/null 2>&1 || true; done; docker network rm $NET >/dev/null 2>&1 || true; }
cleanup
docker network create $NET >/dev/null
docker build -q -f "$ROOT/docker/fake-device.Dockerfile" -t espface-fake "$ROOT" >/dev/null
docker build -q -f "$ROOT/server/renderer/Dockerfile" -t espface-renderer "$ROOT" >/dev/null
fake() { name=$1; shift; docker run -d --network $NET --name espface-e2e-$name espface-fake "$@" >/dev/null; }
fake fake --pin=1234
fake drop --pin=1234 --drop-every 8
fake slow --slow-ui
fake huge --huge-ui
fake busy --max-clients 1
fake flaky --pin=1234 --flaky-auth
fake lock --pin=1234
docker run -d --network $NET --name espface-e2e-web espface-renderer >/dev/null
set +e
docker run --rm --network $NET -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT":/w -w /w/web \
  -e E2E_BASE=http://espface-e2e-web -e E2E_DEVICE=espface-e2e-fake:8080 \
  -e E2E_DEVICE_DROP=espface-e2e-drop:8080 -e E2E_DEVICE_SLOW=espface-e2e-slow:8080 -e E2E_DEVICE_HUGE=espface-e2e-huge:8080 \
  -e E2E_DEVICE_BUSY=espface-e2e-busy:8080 -e E2E_DEVICE_FLAKY=espface-e2e-flaky:8080 -e E2E_DEVICE_LOCK=espface-e2e-lock:8080 \
  "$PW_IMAGE" npx playwright test "$@"
rc=$?
set -e
cleanup
exit $rc
