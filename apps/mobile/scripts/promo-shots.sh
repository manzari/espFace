#!/usr/bin/env sh
# Renders the landing page's phone screenshots (test/screenshots_test.dart at 1080x2424) into promo/images as 720x1616 JPEGs.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
DOCKER_EXTRA="-e ESPFACE_PROMO_SHOTS=1" FLUTTER_CMD=sh "$HERE/flutter.sh" -c "rm -rf build/promo-shots && flutter test test/screenshots_test.dart"
docker run --rm -e OWNER="$(id -u):$(id -g)" -v "$REPO":/w -w /w alpine:3.22 sh -c "
  apk add -q --no-cache imagemagick imagemagick-jpeg >/dev/null 2>&1 || exit 1
  set -e
  mkdir -p promo/images
  rm -f promo/images/phone-*.jpg
  for f in apps/mobile/build/promo-shots/*.png; do
    magick \$f -resize 720x1616 -strip -interlace JPEG -sampling-factor 4:4:4 -quality 85 promo/images/phone-\$(basename \${f%.png}).jpg
  done
  rm -rf apps/mobile/build/promo-shots
  chown \$OWNER promo/images promo/images/phone-*.jpg
"
