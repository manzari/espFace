# Transports

All transports carry the same JSON messages and share one session layer: PIN, tokens, `ESPFACE_MAX_CLIENTS`. A UI does not know which transport a client uses.

| Transport | Call | Build requirement | Binary OTA push |
|---|---|---|---|
| WebSocket + http | on by default | WiFi | yes |
| Stream (UART, USB CDC, any `Stream`) | `face.serial(Serial)` | none | no |
| BLE (NimBLE) | `face.ble()` | `-DESPFACE_BLE`, NimBLE-Arduino | no |
| Bluetooth Classic SPP | `face.btClassic("Name")` | `-DESPFACE_BT_CLASSIC`, classic ESP32 | no |

## WebSocket

The server listens on port 80 at `ws://<host>/ws` and also serves the bootstrap page and `POST /update`. It needs WiFi (`face.wifi().autoConnect()`). If another server owns port 80, change it with `face.setPort(8080)`. `face.enableWs(false)` before `begin()` turns the server off, for BLE-only or serial-only builds. One message per text frame; binary frames carry OTA data only.

## BLE

```cpp
// build_flags = -DESPFACE_BLE, lib_deps = h2zero/NimBLE-Arduino@^2.5.1
face.ble().setName("Boiler");
```

- GATT service `0000ea00-0000-1000-8000-00805f9b34fb`. RX `0000ea01-...` is written by the client, TX `0000ea02-...` notifies, `0000ea03-...` is a read-only characteristic with `name`, a NUL byte and the id. Scanners read it without opening a session.
- Each packet is `[seq][flags][payload]`. Flags bit 0 marks the last chunk, bit 1 the first. The client requests an MTU of 512; the device accepts up to 512 (509 bytes of payload). Both sides chunk against the negotiated MTU.
- The client must subscribe to TX notifications before it sends `hello`. A sequence gap discards the partial message, a duplicate packet is ignored.
- Up to `ESPFACE_BLE_MAX_CONN` (2) centrals can connect, each with its own session.
- A large `ui` arrives chunked and takes a moment; the app shows a progress chip.

::: warning RAM
BLE together with WiFi on a classic ESP32 wants 100 KB of free heap or more. For tight sketches use a BLE-only build (`face.enableWs(false)` and no WiFi), as the `BleOnly` example does.
:::

## Stream, UART and USB CDC

```cpp
face.logTo(nullptr);              // keep library log lines off the wire when sharing Serial
face.enableWs(false);
face.begin("SerialOnly");
face.serial(Serial);              // one client per stream
// face.serial(Serial1, "uart").setIdleTimeout(60000);
```

- One JSON message per `\n`-terminated line, `\r` and empty lines ignored, lines over 2048 bytes discarded with err 2.
- One session per stream. It opens on the first line, a new `hello` restarts it, and `setIdleTimeout(ms)` closes it after silence (default off). Clients ignore lines that are not a JSON object.
- When the UI shares `Serial` with the logs, call `face.logTo(nullptr)` or `face.logTo(&Serial1)`.
- The Android app speaks to it through USB OTG (CP210x, CH340/CH9102, FTDI and Espressif adapters, 8N1, baud per device, default 115200). On a PC any terminal shows the JSON lines.

## Bluetooth Classic SPP

```cpp
// build_flags = -DESPFACE_BT_CLASSIC   (classic ESP32 only)
face.enableWs(false);
face.btClassic("Boiler");
```

A stream transport over `BluetoothSerial`. The session follows the SPP link. It uses Bluedroid and is mutually exclusive with `ESPFACE_BLE` in one build (enforced by `#error`). It needs a larger app partition: Arduino IDE "Minimal SPIFFS" or "Huge APP", PlatformIO `board_build.partitions = min_spiffs.csv`. The device must be paired in the phone's system settings first; Android only.

## What each transport supports

Everything except binary frames. Because BLE and streams have no binary frames, `ota.begin` is answered with err 8 there, while `ota.url` works. Messages from client to device are capped at 2048 bytes (`ESPFACE_MAX_MSG`).

## App fallback order and pinning

A saved device can carry several addresses. The app tries WiFi first, then BLE, then serial, and skips a medium that failed to open for the next attempt; one that opened and then dropped is retried first. In the device's System page you can pin one with "Preferred transport".

## Footprint

Measured on esp32dev as deltas against `Minimal` (see `footprint.md` from CI):

| Addition | Static RAM | Flash |
|---|---|---|
| Stream transport | none (2 KB heap line buffer per instance) | about 28 KB |
| NimBLE (`BleOnly`) | about 11 KB | about 270 KB |
| Bluedroid SPP (`BtClassic`) | about 14 KB | about 755 KB |

The heap the stacks take at runtime is not measured; NimBLE's own figure is roughly 100 KB below Bluedroid.
