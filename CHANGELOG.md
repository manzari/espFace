# Changelog

All notable changes to espFace are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html), with one house rule: version numbers never contain the
digit 4 (0.3.0 is followed by 0.5.0, 1.3.x by 1.5.0).

Component notes shown by registries: [`firmware/CHANGELOG.md`](firmware/CHANGELOG.md) (Arduino library, PlatformIO),
the mobile app's store notes in `apps/mobile/`.

## [Unreleased]

## [1.0.0] - 2026-10-14

First public release. Protocol v1 is stable; the hosted web renderer at `/r/1/` is frozen
(see [`web/RENDERER-VERSIONING.md`](web/RENDERER-VERSIONING.md)).

### Protocol (`protocol/`)
- `PROTOCOL.md` v1: JSON messages over WebSocket, BLE (chunked) and line-framed streams; `hello`, `auth`, `time`,
  `ui`, `upd`, `set`, `ev`, `pts`, `log`, `toast`, `prop`, `dlg`, `page`, `sys`, `err`.
- 30 widget types, pages, groups and rows; HMAC-SHA256 PIN pairing with session tokens and lockout.
- JSON Schema (draft 2020-12) and test vectors shared by firmware, web renderer and app.
- Client limits, auth timeout, dialog and set-echo rules.

### Firmware library (`firmware/`, Arduino and PlatformIO name `espFace`)
- Core: `begin`/`loop`, UI builder with pages, rows and groups, `upd`/`set`/`ev`, per-UI PIN auth, persisted inputs
  in NVS, `prop` show/hide, device dialogs, client clock, active-page filtering, multiple UIs, callbacks, `face.delay`.
- All 30 widgets including joystick, dpad, hold button, log with history replay, table, map, stream, clock, charts.
- Transports: WebSocket (esp_http_server), NimBLE with chunking, UART/USB CDC streams, Bluetooth Classic SPP.
- System: captive portal and WiFi provisioning, OTA (push, `ota.url`, `POST /update`), device info, reboot reason,
  NTP, direct ntfy notifications, PIN change, bootstrap page loading the hosted renderer.
- Hardening: client limit, reconnect handling, RAM soak tests, ESP32/S2/S3/C3/C6 build matrix, footprint budget in CI.
- Examples: Minimal, FullDemo, EmbeddedWeb, Notify, BleOnly, SerialOnly, Provisioning, BtClassic.

### Web renderer (`web/`, served at `/r/1/`)
- Preact renderer for every widget, pages, rows, dialogs, toasts, charts and logs, pairing dialog, theme settings.
- System pages: WiFi, OTA push, info, opt-in release check, reboot, PIN change, console.
- Reconnect with jittered exponential backoff, token resume, lockout countdown, bounded buffers.
- Hosted site: landing page `/`, connect page `/connect/`, WebSerial flash page `/flash/`, docs `/docs/`.
- Renderer version shown on the system page.

### Mobile app (`apps/mobile/`)
- Flutter app for Android and iOS over WiFi, BLE, USB serial and Bluetooth Classic, with mDNS discovery, QR scan,
  pairing, native rendering of all widgets, system pages and white-label flavour. See the app's own release notes.

### Tools and docs
- Fake device (`tools/fake-device/`) with network fault knobs for client tests.
- Documentation site (`docs/site/`, VitePress) with guides, widget catalogue and generated API reference.
- Forgejo Actions CI for protocol, firmware (native + chip matrix), web, docs and app; tag-triggered release workflow.

[Unreleased]: https://git.hauptstadt.monster/manzari/espFace/compare/v1.0.0...main
[1.0.0]: https://git.hauptstadt.monster/manzari/espFace/releases/tag/v1.0.0
