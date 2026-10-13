#!/usr/bin/env sh
# Runs flutter (or $FLUTTER_CMD) inside the Docker image; pub and gradle caches live in named volumes.
# Usage: scripts/flutter.sh test            FLUTTER_CMD=dart scripts/flutter.sh format .
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
IMAGE=${FLUTTER_IMAGE:-inhumane-flutter:latest}
CMD=${FLUTTER_CMD:-flutter}
exec docker run --rm ${DOCKER_TTY:--i} \
  -v "$REPO":/w -w /w/apps/mobile \
  -v espface-flutter-pub:/root/.pub-cache \
  -v espface-gradle:/root/.gradle \
  -e PUB_CACHE=/root/.pub-cache \
  -e ESPFACE_FAKE_WS="${ESPFACE_FAKE_WS:-}" \
  --add-host=host.docker.internal:host-gateway \
  ${DOCKER_EXTRA:-} \
  "$IMAGE" "$CMD" "$@"
