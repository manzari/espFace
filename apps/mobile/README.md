# espFace mobile app (Flutter)

Native Android/iOS renderer for espFace protocol v1 (`protocol/PROTOCOL.md`). Phase 3 scope: WiFi/WebSocket transport, discovery, PIN pairing, all 30 widget types, pages, dialogs, toasts, charts/logs, device groups, theme settings, white-label flavors and the device system pages (info, WiFi provisioning, OTA push/URL, PIN, revoke, reboot, optional GitHub release check). BLE and serial transports arrive in phase 5 behind the same `Transport` interface.

## Build and test (Docker only)

Nothing is installed on the host. `scripts/flutter.sh` runs `flutter` inside the image `inhumane-flutter:latest` (Flutter 3.44.0, Android platform 36) with named volumes for the pub and gradle caches. `docker/flutter.Dockerfile` builds an equivalent image for CI (`FLUTTER_IMAGE=...` selects another image).

```sh
cd apps/mobile
scripts/flutter.sh pub get
scripts/flutter.sh analyze
scripts/flutter.sh test                                   # unit + widget tests, offline
scripts/flutter.sh build apk --debug                      # build/app/outputs/flutter-apk/app-debug.apk
FLUTTER_CMD=dart scripts/flutter.sh format lib test       # dart instead of flutter
```

Smoke test against the reference fake device (host port 8080 is often taken, use 18080):

```sh
docker build -f docker/fake-device.Dockerfile -t espface-fake . && docker run --rm -d --name espface-fake -p 18080:8080 espface-fake --pin=1234
ESPFACE_FAKE_WS=ws://host.docker.internal:18080/ws scripts/flutter.sh test test/integration/fake_device_test.dart
```

The integration test is skipped unless `ESPFACE_FAKE_WS` is set, so plain `flutter test` stays offline.

Restricted networks: on hosts where `dl.google.com` is unreachable (Google Maven and the SDK manager answer 404) the Android build cannot fetch AGP, androidx, ML Kit or an NDK. `scripts/flutter.sh` then mounts `scripts/gradle-env.init.gradle.kts` and extra SDK parts from a Docker volume:

```sh
ESPFACE_MAVEN_MIRROR=https://repo.huaweicloud.com/repository/maven/ \
ESPFACE_SDK_EXTRAS_VOLUME=<volume with ndk/<ver> and cmake/> ESPFACE_NDK_VERSION=27.1.12297006 ESPFACE_COMPILE_SDK=36 \
scripts/flutter.sh build apk --debug
```

The mirror is only a fallback repository (Google first), the NDK is needed by the `jni` package behind `file_picker`, and `ESPFACE_COMPILE_SDK` lifts plugins pinned to an older platform to the one installed in the image. None of this is used on CI. iOS needs a Mac for building; the Info.plist already carries the local-network, Bonjour (`_espface._tcp`), camera and Bluetooth usage strings.

Run on a device: `scripts/flutter.sh run` needs USB passthrough into the container; the usual path is installing the APK (`adb install build/app/outputs/flutter-apk/app-debug.apk`) from a host that has adb.

## White-label builds

Everything is a `--dart-define`; no fork needed:

| define | effect |
|---|---|
| `ESPFACE_APP_NAME=AcmeCtl` | title in the app (Android label stays `espFace` unless `strings.xml` is changed too) |
| `ESPFACE_ACCENT=#112233` | fixed seed color; disables dynamic color and the accent setting |
| `ESPFACE_PROJ=Acme` | only devices with this `proj` are listed and discovered |
| `ESPFACE_DEVICES=Boiler@10.0.0.5,Pump@pump.local:8080` | locked device list: no add/remove/reorder |
| `ESPFACE_RELEASE_CHECK=on` | enable the (still user-triggered) GitHub release check by default |

```sh
scripts/flutter.sh build apk --debug --dart-define=ESPFACE_APP_NAME=AcmeCtl --dart-define=ESPFACE_ACCENT=#112233 --dart-define=ESPFACE_PROJ=Acme
```

## Layout

```
lib/
  main.dart                      ProviderScope + SharedPreferences bootstrap
  app/                           MaterialApp.router, go_router routes, Material 3 theme (dynamic color, accent, font scale, wide), settings page, Flavor
  core/transport/                Transport interface + WsTransport (BLE/stream come in phase 5)
  core/proto/                    hand-written message models (HelloMsg, UiMsg/WidgetDef, ...), codec, C2d builders, HMAC-SHA256, value formatting
  core/session/                  Session state machine (hello -> auth -> time, reconnect/backoff, lockout), TokenStore (flutter_secure_storage)
  features/devices/              SavedDevice list (shared_preferences, grouped by proj, reorder), mDNS discovery (nsd), QR scan (mobile_scanner), add sheet
  features/render/               UiStore (immutable widget model, per-key listeners, chart/log ring buffers, dialogs, toasts, layout), one widget per `ty`, pages, overlays
  features/system/               system page sections (info, WiFi, security, reboot, OTA push + URL, release check, console, connection), OtaPush, release lookup
test/
  codec_test.dart                decode every protocol vector, C2d builders vs vectors, HMAC vector, widget defaults
  session_test.dart              state machine with a scripted FakeTransport (pin, token reuse, lockout, reconnect, page resend)
  store_test.dart                layout from the showcase vector, upd/prop/pts/log/dlg/toast/sys handling
  widgets_test.dart              every renderer widget type incl. interactions, layout rows and folding groups
  overlays_test.dart             device dialogs, toasts, PIN dialog
  system_test.dart               flavor parsing, discovery/QR mapping, ws url, release info, OTA chunking
  integration/fake_device_test.dart   real WsTransport against the fake device (env-gated)
```

Renderer rules: `ui` builds an immutable model, `upd` only notifies the touched widget ids, `prop` patches a widget in place (structural props rebuild the layout), unknown widget types render an "unsupported widget" placeholder, unknown messages and keys are ignored. The app never talks to the internet except the user-triggered release check (off by default) and map tiles for the `map` widget.
