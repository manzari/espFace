# Compile-time options

Define these as build flags (`-DNAME=value` in PlatformIO `build_flags`) or before including `espFace.h`.

| Option | Default | Meaning |
|---|---|---|
| `ESPFACE_MAX_CLIENTS` | 4 | Maximum concurrent sessions across all transports; the next client gets err 9 |
| `ESPFACE_LOG_HISTORY` | 0 | Number of log lines kept on the device and replayed to a client that connects later |
| `ESPFACE_RENDERER_HOST` | `https://espface.manzari.dev` | Host the bootstrap page loads the renderer from. Use a quoted string: `-DESPFACE_RENDERER_HOST=\"https://your.host\"` |
| `ESPFACE_FRAME_SIZE` | 1024 | Size of the frames the `ui` message is streamed in |
| `ESPFACE_MAX_MSG` | 2048 | Largest accepted client-to-device message and stream line, in bytes |
| `ESPFACE_NO_TLS` | off | Drop TLS: OTA and ntfy are http-only, https URLs fail with a log line |
| `ESPFACE_EMBED_WEB` | off | Serve the gzipped renderer from flash (generate it with `tools/embed-web.py`) |
| `ESPFACE_BLE` | off | Enable the NimBLE transport; needs `h2zero/NimBLE-Arduino@^2.5.1` |
| `ESPFACE_BLE_MTU` | 512 | MTU the device accepts |
| `ESPFACE_BLE_MAX_CONN` | 2 | Maximum BLE centrals |
| `ESPFACE_BT_CLASSIC` | off | Enable Bluetooth Classic SPP (Bluedroid, classic ESP32 only); excludes `ESPFACE_BLE` |

## Runtime setters

| Call | Effect |
|---|---|
| `face.setPort(port)` | HTTP and WebSocket port (default 80, falls back to 8080 if the bind fails) |
| `face.setRendererHost("https://host")` | Renderer host at runtime, overrides the compile-time default |
| `face.enableWs(false)` | Skip the http and WebSocket server; call before `begin()` |
| `face.logTo(Print*)` | Where library log lines go; `nullptr` silences them |
| `face.setOtaCaCert(pem)` | CA certificate for https downloads and ntfy |
| `face.ntfyRateLimit(ms)` | Minimum time between ntfy messages (default 10000) |
| `face.serial(stream).setIdleTimeout(ms)` | Close a stream session after silence (default off) |

## Examples

Each example lives in `firmware/examples/<Name>`. An example directory may carry `build_flags`, `lib_deps`, `boards` and `project_options` files that `tools/ci-build.sh` applies.

| Example | What it shows | Special build needs |
|---|---|---|
| `Minimal` | Gauge and switch | none |
| `FullDemo` | Every widget, PIN, OTA, NTP, ntfy | none |
| `EmbeddedWeb` | Renderer served from flash | `-DESPFACE_EMBED_WEB` and a generated `embed.h` |
| `Notify` | ntfy alerts | none |
| `SerialOnly` | UI on USB serial, no WiFi | none |
| `BleOnly` | UI over BLE, no WiFi | `-DESPFACE_BLE`, NimBLE-Arduino |
| `Provisioning` | Main UI on WiFi, open setup UI on BLE via `addUi` | `-DESPFACE_BLE`, NimBLE-Arduino |
| `BtClassic` | UI over Bluetooth SPP | `-DESPFACE_BT_CLASSIC`, esp32dev only, larger partition |
