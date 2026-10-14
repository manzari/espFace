# espFace mobile app (Flutter)

Native Android/iOS renderer for espFace protocol v1 (`protocol/PROTOCOL.md`). Phase 3 scope: WiFi/WebSocket transport, discovery, PIN pairing, all 30 widget types, pages, dialogs, toasts, charts/logs, device groups, theme settings, white-label flavors and the device system pages (info, WiFi provisioning, OTA push/URL, PIN, revoke, reboot, optional GitHub release check). Phase 5 adds BLE, USB OTG serial and Bluetooth Classic SPP behind the same `Transport` interface, with per-device transport fallback.

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

The integration test is skipped unless `ESPFACE_FAKE_WS` is set, so plain `flutter test` stays offline. `test/integration/hardening_test.dart` is gated the same way per knob: `ESPFACE_FAKE_WS_DROP` (`--pin=1234 --drop-every 8`), `ESPFACE_FAKE_WS_SLOW` (`--slow-ui`), `ESPFACE_FAKE_WS_HUGE` (`--huge-ui`), `ESPFACE_FAKE_WS_BUSY` (`--max-clients 1`), `ESPFACE_FAKE_WS_FLAKY` (`--pin=1234 --flaky-auth`); CI starts one fake device per knob on ports 18081 to 18085.

## Release builds (phase 7)

Version 1.0.0, release signing from `android/key.properties` or `ESPFACE_KEYSTORE*` env vars (unsigned with a warning otherwise), R8, per-ABI versionCodes without the digit 4, FOSS-only dependencies, launcher icons from `assets/icon/*.svg` (`scripts/icons.sh`), store metadata and generated screenshots under `fastlane/`, F-Droid metadata under `fdroid/`. Steps per store: [RELEASE.md](RELEASE.md).

## Reconnecting (phase 6)

`Session` reconnects with exponential backoff 500 ms × 2^n, ±25 % jitter, capped at 30 s (`backoffDelay`); `reconnect()` is immediate and replaces a pending retry. The `UiStore` keeps the UI model across drops (only per-connection state is reset), the banner shows a countdown and a "Retry now" button, `err` 9 on hello is shown as "Device is full", and `err` 5 after a correct PIN is retried once with a fresh nonce before the dialog asks again. `sessionProvider` wires an `AppLifecycleListener`: in the background no reconnects are attempted (`setBackground(true)` cancels the pending retry, an open link is kept), returning to the foreground reconnects at once. Buffers are bounded (chart series 5000 points, log widgets 2000 lines, console 500, toasts 5, dialogs 10) and buffers of widgets missing from a new `ui` are released. `PageBody` renders every card as a lazy sliver (`SliverList.builder` inside `DecoratedSliver`/`SliverMainAxisGroup`) so a UI with hundreds of widgets only builds what is visible; `test/hardening_test.dart` prints the first-frame time for 600 widgets. `transportFactoryProvider` lets tests replace the real transports; the provider disposal test checks that leaving the device screen closes the transport and stops retries.

Restricted networks: on hosts where `dl.google.com` is unreachable (Google Maven and the SDK manager answer 404) the Android build cannot fetch AGP, androidx or an NDK. `scripts/flutter.sh` then mounts `scripts/gradle-env.init.gradle.kts` and extra SDK parts from a Docker volume:

```sh
ESPFACE_MAVEN_MIRROR=https://repo.huaweicloud.com/repository/maven/ \
ESPFACE_SDK_EXTRAS_VOLUME=<volume with ndk/<ver> and cmake/> ESPFACE_NDK_VERSION=27.1.12297006 ESPFACE_COMPILE_SDK=36 \
scripts/flutter.sh build apk --debug
```

The mirror is only a fallback repository (Google first), the NDK is needed by the `jni` package behind `file_picker`, and `ESPFACE_COMPILE_SDK` lifts plugins pinned to an older platform to the one installed in the image. None of this is used on CI. iOS needs a Mac for building; the Info.plist already carries the local-network, Bonjour (`_espface._tcp`), camera and Bluetooth usage strings.

Run on a device: `scripts/flutter.sh run` needs USB passthrough into the container; the usual path is installing the APK (`adb install build/app/outputs/flutter-apk/app-debug.apk`) from a host that has adb.

## Transports

All media speak the same JSON protocol; the `Session` never knows which one it is on. A saved device can carry several addresses and the connection tries them in this order unless the user pins one in the device's System page ("Preferred transport"): a medium that fails to open is skipped for the next attempt, one that opened and then dropped is retried first.

| Transport | Package | Address | Binary frames | Notes |
|---|---|---|---|---|
| WiFi | `web_socket_channel` | `host[:port]` | yes (OTA push) | mDNS discovery, manual host, QR |
| BLE | `flutter_blue_plus` 1.36.8 | platform device id | no | scan filtered on service `0000ea00-…`, INFO characteristic read on add (`name\0id`), MTU 512 requested, write-without-response, `[seq][flags][payload]` chunking from `core/transport/ble_framer.dart` (mirror of the firmware `BleFramer.h`), progress chip while a chunked `ui` arrives |
| USB OTG serial | `usb_serial` 0.5.2 (vendored, see below) | `vid:pid` (hex) | no | Android only. 8N1, baud per device (default 115200, selectable in the add sheet and the System page). Android asks for USB permission on first open; adapters listed in `res/xml/device_filter.xml` (Espressif, CP210x, CH340/CH9102, FTDI) also offer the app when plugged in |
| Bluetooth Classic SPP | `flutter_blue_classic` 0.1.1 | MAC | no | Android only, device must be paired in the system settings first; the add sheet lists paired devices |

Per-transport limits (PROTOCOL.md 2): BLE and streams have no binary frames, so the OTA section hides the push half ("OTA push needs WiFi") and keeps `ota.url`; the firmware answers `ota.begin` with err 8 there anyway. C→D messages are capped at 2048 bytes by the device; the app accepts up to 64 KB per message/line on BLE and streams (the `ui` can exceed 4 KB). Stream lines that are not a JSON object (boot ROM output, log lines) are dropped by `LineFramer`. BLE: a seq gap drops the partial message, a duplicate packet is ignored, an oversize message is skipped to its last chunk (same rules as the firmware).

Package choices, for the record: `flutter_blue_plus` 2.x switched to a licence that charges for-profit use, so the app pins the last BSD-3 release (1.36.8, Android plugin 7.0.4). `flutter_bluetooth_serial` (2021) and `usb_serial` 0.5.2 (2024) still call `jcenter()`, which Gradle 9 removed; the SPP side uses the maintained `flutter_blue_classic` instead and `usb_serial` is vendored under `third_party/usb_serial/` (MIT) with only `android/build.gradle` rewritten for AGP 9. `permission_handler` 13 needs Android platform 37 which the image lacks, so permissions are left to `flutter_blue_plus` (it requests them at scan/connect time) and a denial is surfaced as `PermissionDenied` with a "Settings" button that opens the app's settings page through a 10-line method channel in `MainActivity.kt`.

Permissions (Android): `BLUETOOTH_SCAN` (`neverForLocation`) and `BLUETOOTH_CONNECT` on 12+, `BLUETOOTH`/`BLUETOOTH_ADMIN`/`ACCESS_FINE_LOCATION` with `maxSdkVersion=30` for older releases, `android.hardware.usb.host` feature (not required). iOS: the existing `NSBluetoothAlwaysUsageDescription`; BLE background mode is not needed (the app only talks to devices while open). USB and SPP sections are hidden on iOS (`serialSupportedProvider`).

BLE, USB and SPP radio behaviour is not covered by CI (no hardware in Docker); the transports are tested against fakes (`test/ble_transport_test.dart` runs a session through a fake GATT layer that executes the firmware-side chunker, `test/stream_transport_test.dart` through an in-memory serial pipe).

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
  app/                           MaterialApp.router, go_router routes, Material 3 theme (dynamic color, accent, font scale, wide), settings page, Flavor, session provider + transport factory
  core/transport/                Transport interface, WsTransport, BleTransport (+ ble_gatt.dart: GATT abstraction over flutter_blue_plus, ble_framer.dart), StreamTransport (+ line_framer.dart) with UsbSerialTransport and BtClassicTransport, TransportChooser (fallback order / pin)
  core/platform/                 app settings deep link (method channel)
  core/proto/                    hand-written message models (HelloMsg, UiMsg/WidgetDef, ...), codec, C2d builders, HMAC-SHA256, value formatting
  core/session/                  Session state machine (hello -> auth -> time, reconnect/backoff, lockout), TokenStore (flutter_secure_storage)
  features/devices/              SavedDevice list (shared_preferences, grouped by proj, reorder, per-transport addresses), mDNS discovery (nsd), BLE scan / USB ports / paired SPP providers, QR scan (qr_code_dart_scan: pure-Dart ZXing over the camera plugin, no ML Kit), add sheet with WiFi/BLE/USB/Bluetooth sections
  features/render/               UiStore (immutable widget model, per-key listeners, chart/log ring buffers, dialogs, toasts, layout), one widget per `ty`, pages, overlays, transport chip
  features/system/               system page sections (info, WiFi, security, reboot, OTA push + URL, release check, console, connection with transport pin and USB baud), OtaPush, release lookup
third_party/usb_serial/          vendored usb_serial 0.5.2 (MIT) with a Gradle 9 build file
test/
  codec_test.dart                decode every protocol vector, C2d builders vs vectors, HMAC vector, widget defaults
  session_test.dart              state machine with a scripted FakeTransport (pin, token reuse, lockout, reconnect, page resend)
  hardening_test.dart            backoff, drop keeps UI + token resume, busy, flaky auth, background pause/resume, immediate reconnect, dispose, provider disposal, buffer bounds, lazy layout with 600 widgets
  ble_framer_test.dart           chunker/reassembler: roundtrip at MTU 23/185/512, seq wrap, gap, duplicate, oversize, stray continuation
  line_framer_test.dart          split/joined/CRLF/empty/oversize lines
  stream_transport_test.dart     hello -> auth -> ui through Session over an in-memory serial pipe, noise lines, link drop + reconnect
  ble_transport_test.dart        BleTransport against a fake GATT layer: MTU-sized packets, write-without-response, reassembly + receiving flag, disconnect, permission denial, full session at MTU 23
  transports_test.dart           SavedDevice addresses/json/key/candidates/merge, TransportChooser rotation and pin
  add_sheet_test.dart            add sheet sections (WiFi, BLE with INFO read and record merge, USB with baud, Bluetooth, iOS hiding)
  store_test.dart                layout from the showcase vector, upd/prop/pts/log/dlg/toast/sys handling
  widgets_test.dart              every renderer widget type incl. interactions, layout rows and folding groups
  overlays_test.dart             device dialogs, toasts, PIN dialog
  system_test.dart               flavor parsing, discovery/QR mapping, ws url, release info, OTA chunking
  screenshots_test.dart          store screenshots: real app against a scripted demo device, PNGs with ESPFACE_SCREENSHOTS=1
  integration/fake_device_test.dart   real WsTransport against the fake device (env-gated)
  integration/hardening_test.dart     drop-every, slow-ui, huge-ui, max-clients, flaky-auth against fake devices with knobs (env-gated per knob)
```

Renderer rules: `ui` builds an immutable model, `upd` only notifies the touched widget ids, `prop` patches a widget in place (structural props rebuild the layout), unknown widget types render an "unsupported widget" placeholder, unknown messages and keys are ignored. The app never talks to the internet except the user-triggered release check (off by default) and map tiles for the `map` widget.
