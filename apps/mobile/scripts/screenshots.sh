#!/usr/bin/env sh
# Regenerates the store screenshots (test/screenshots_test.dart) and strips alpha (Play wants 24-bit PNG).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$HERE/.." && pwd)
DIR=fastlane/metadata/android/en-US/images/phoneScreenshots
rm -f "$APP/$DIR"/*.png
DOCKER_EXTRA="-e ESPFACE_SCREENSHOTS=1" "$HERE/flutter.sh" test test/screenshots_test.dart
docker run --rm -e OWNER="$(id -u):$(id -g)" -v "$APP":/a -w /a alpine:3.22 sh -c "
  apk add -q --no-cache imagemagick >/dev/null 2>&1 || exit 1
  for f in $DIR/*.png; do magick \$f -alpha off \$f; done
  chown \$OWNER $DIR $DIR/*.png
"
