# espFace library changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Version numbers never contain the digit 4.
Project-wide notes: https://git.hauptstadt.monster/manzari/espFace/src/branch/main/CHANGELOG.md

## [Unreleased]

### Changed
- The web renderer is always served from flash at `/r/1/` (about 60 KB gzipped, no RAM; browsers revalidate it by
  ETag). The bootstrap page loads it from the device, so the web UI and the captive portal work without internet.
  `ESPFACE_EMBED_WEB` and the `EmbeddedWeb` example are gone, it is the default now.

### Removed
- `ESPFACE_RENDERER_HOST` and `EspFace::setRendererHost()`: the bootstrap page no longer loads anything from a host
  (the setter never had an effect in 1.0.0).

## [1.0.0] - 2026-10-14

First public release, protocol v1.

### Added
- UI builder: pages, groups, rows and 30 widget types (label, button with hold, switch, slider, number with spin,
  text, textarea, select, flags, color, datetime, joystick, dpad, gauge, progress, display, led, chart, log, table,
  image, stream, clock, map, textblock, header, spacer, group, page, row).
- Values and events (`upd`, `set`, `ev`), chart points, logs with history replay, toasts, device dialogs, `prop`
  updates (show/hide, labels, ranges), persisted inputs in NVS, multiple UIs, connect/disconnect/reboot callbacks.
- PIN pairing with HMAC-SHA256, session tokens and lockout.
- Transports: WebSocket, NimBLE (chunked, MTU 512, 2 centrals), UART/USB CDC streams, Bluetooth Classic SPP
  (`ESPFACE_BT_CLASSIC`), `face.enableWs(false)`, `face.logTo()`.
- System features: captive portal and WiFi provisioning, OTA push, `ota.url` and `POST /update`, device info and
  reboot reason, NTP helper, direct ntfy notifications, PIN change, bootstrap page loading the renderer from
  `ESPFACE_RENDERER_HOST` (default `https://espface.manzari.dev`, `/r/1/`).
- Supported chips: ESP32, ESP32-S2, ESP32-S3, ESP32-C3 (ESP32-C6 on the pioarduino platform).
- Examples: Minimal, FullDemo, EmbeddedWeb, Notify, BleOnly, SerialOnly, Provisioning, BtClassic.
