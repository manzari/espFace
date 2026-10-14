#!/usr/bin/env sh
# Renders assets/icon/*.svg to PNGs (Alpine + rsvg in Docker), then runs flutter_launcher_icons for Android/iOS.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "$HERE/.." && pwd)
IMG=fastlane/metadata/android/en-US/images
docker run --rm -e OWNER="$(id -u):$(id -g)" -v "$APP":/a -w /a alpine:3.22 sh -c "
  apk add -q --no-cache rsvg-convert imagemagick font-inter >/dev/null 2>&1 || exit 1
  set -e
  mkdir -p $IMG
  rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg | magick - -alpha off assets/icon/icon.png
  rsvg-convert -w 432 -h 432 assets/icon/foreground.svg -o assets/icon/foreground.png
  rsvg-convert -w 432 -h 432 assets/icon/monochrome.svg -o assets/icon/monochrome.png
  rsvg-convert -w 512 -h 512 assets/icon/icon.svg | magick - -alpha off $IMG/icon.png
  rsvg-convert -w 1024 -h 500 assets/icon/feature.svg | magick - -alpha off $IMG/featureGraphic.png
  chown \$OWNER assets/icon/*.png $IMG $IMG/*.png fastlane fastlane/metadata fastlane/metadata/android fastlane/metadata/android/en-US
"
FLUTTER_CMD=dart "$HERE/flutter.sh" run flutter_launcher_icons
# flutter_launcher_icons 0.14.4 rewrites this Xcode setting by mistake; restore it.
sed -i 's/SYMBOL_EXTENSIONS = AppIcon;/SYMBOL_EXTENSIONS = YES;/' "$APP/ios/Runner.xcodeproj/project.pbxproj"
