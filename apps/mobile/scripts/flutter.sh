#!/usr/bin/env sh
# Runs flutter (or $FLUTTER_CMD) inside the Docker image; pub and gradle caches live in named volumes.
# Usage: scripts/flutter.sh test            FLUTTER_CMD=dart scripts/flutter.sh format .
# Restricted networks (dl.google.com unreachable), see README:
#   ESPFACE_MAVEN_MIRROR=https://repo.huaweicloud.com/repository/maven/   gradle fallback repository
#   ESPFACE_SDK_EXTRAS_VOLUME=<docker volume with ndk/ and cmake/>         mounted into the Android SDK
#   ESPFACE_NDK_VERSION=27.1.12297006                                      NDK version from that volume
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
IMAGE=${FLUTTER_IMAGE:-inhumane-flutter:latest}
CMD=${FLUTTER_CMD:-flutter}
SDK=${ANDROID_SDK_DIR:-/opt/android-sdk-linux}
EXTRA=""
if [ -n "${ESPFACE_MAVEN_MIRROR:-}${ESPFACE_NDK_VERSION:-}${ESPFACE_COMPILE_SDK:-}" ]; then
  EXTRA="$EXTRA -v $HERE/gradle-env.init.gradle.kts:/root/.gradle/init.d/espface-env.init.gradle.kts:ro"
fi
if [ -n "${ESPFACE_SDK_EXTRAS_VOLUME:-}" ]; then
  EXTRA="$EXTRA --mount type=volume,src=$ESPFACE_SDK_EXTRAS_VOLUME,dst=$SDK/ndk,volume-subpath=ndk,readonly"
  EXTRA="$EXTRA --mount type=volume,src=$ESPFACE_SDK_EXTRAS_VOLUME,dst=$SDK/cmake,volume-subpath=cmake,readonly"
fi
exec docker run --rm ${DOCKER_TTY:--i} \
  -v "$REPO":/w -w /w/apps/mobile \
  -v espface-flutter-pub:/root/.pub-cache \
  -v espface-gradle:/root/.gradle \
  $EXTRA \
  -e PUB_CACHE=/root/.pub-cache \
  -e ESPFACE_FAKE_WS="${ESPFACE_FAKE_WS:-}" \
  -e ESPFACE_FAKE_WS_DROP="${ESPFACE_FAKE_WS_DROP:-}" -e ESPFACE_FAKE_WS_SLOW="${ESPFACE_FAKE_WS_SLOW:-}" \
  -e ESPFACE_FAKE_WS_HUGE="${ESPFACE_FAKE_WS_HUGE:-}" -e ESPFACE_FAKE_WS_BUSY="${ESPFACE_FAKE_WS_BUSY:-}" \
  -e ESPFACE_FAKE_WS_FLAKY="${ESPFACE_FAKE_WS_FLAKY:-}" \
  -e ESPFACE_MAVEN_MIRROR="${ESPFACE_MAVEN_MIRROR:-}" \
  -e ESPFACE_NDK_VERSION="${ESPFACE_NDK_VERSION:-}" \
  -e ESPFACE_COMPILE_SDK="${ESPFACE_COMPILE_SDK:-}" \
  -e ESPFACE_KEYSTORE="${ESPFACE_KEYSTORE:-}" -e ESPFACE_KEYSTORE_PASSWORD="${ESPFACE_KEYSTORE_PASSWORD:-}" \
  -e ESPFACE_KEY_ALIAS="${ESPFACE_KEY_ALIAS:-}" -e ESPFACE_KEY_PASSWORD="${ESPFACE_KEY_PASSWORD:-}" \
  --add-host=host.docker.internal:host-gateway \
  ${DOCKER_EXTRA:-} \
  "$IMAGE" "$CMD" "$@"
