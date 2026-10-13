# espFace – Implementation Plan

Status: approved decisions baked in (2026-10-12). Greenfield.

## 1. Goal and scope

espFace gives any ESP32 project an admin/control UI with minimal integration effort.
The ESP *describes* its UI; clients *render* it.

Clients:
- Android app and iOS app (Flutter, one codebase, native renderer, fully offline).
- Web renderer for the captive portal / browser fallback (loaded from our server, optionally embedded in flash).

Decisions taken:
| Topic | Decision |
|---|---|
| Firmware target | ESP32 family only (ESP32, S2, S3, C3, C6), Arduino core 3.x via Arduino IDE and PlatformIO. No ESP8266. |
| Transports v1 | WiFi WebSocket (AP or LAN) + BLE (ESP32 variants with BLE) + any Arduino `Stream` (UART, USB CDC, Bluetooth Classic SPP on classic ESP32). Cloud relay: later, design must not block it. |
| Apps | Flutter, native widget renderer. Android additionally supports USB OTG serial and Bluetooth Classic. |
| Web | Separate TypeScript renderer, same protocol. |
| Security | Optional device PIN with HMAC challenge-response, pairing on first connect, session token, plaintext local. |
| Extra v1 features | Live charts, pages, rows/columns, dialogs, runtime prop updates, persisted inputs, WiFi provisioning, OTA (push and by URL), device info/reboot, client clock sync, optional NTP, direct ntfy notifications. |
| Web hosting | ESP serves ~2 KB bootstrap; renderer from our server; `ESPFACE_EMBED_WEB` build flag embeds a gzipped copy. |
| Release | Open source, MIT for library, web renderer and apps. App id `dev.manzari.espFace`. Play Store, App Store, own F-Droid repo. |

Out of scope v1: cloud relay/MQTT, ESP-IDF-only component, file manager / FS format / static file serving, canvas, custom CSS/JS injection, free absolute layout, ESPHome/MicroPython, user roles.

## 2. Repository layout (monorepo)

```
espFace/
  protocol/            # single source of truth: JSON schema + docs + test vectors
    schema/v1/*.json
    PROTOCOL.md
    vectors/*.json     # message samples used by all three implementations' tests
  firmware/            # Arduino library "espFace"
    library.properties, library.json (PlatformIO)
    src/
    examples/
    test/              # PlatformIO native unit tests (host)
    tools/             # embed-web.py: builds web bundle -> src/web_embed.h
  web/                 # TypeScript renderer (Vite + Preact)
  apps/mobile/         # Flutter app
  tools/fake-device/   # Node implementation of the device side for client dev/CI
  docker/              # Dockerfiles: web build, flutter android build, platformio
  server/              # static hosting config for the renderer (Coolify), later relay
  docs/
```

Each sub-project is independently releasable; the protocol version pins them together.

## 3. Protocol (protocol/)

Transport-agnostic, newline-free JSON messages, one message per WebSocket text frame / per BLE logical packet / per `\n`-terminated line on streams.
Every message has `"t"` (type). Numbers only where needed; keys are short to save ESP RAM. Renderers ignore unknown keys.

### 3.1 Handshake and auth
```
C→D  {"t":"hello","v":1,"client":"app|web","tok":"<session token or absent>"}
D→C  {"t":"hello","v":1,"name":"Boiler","id":"a1b2c3","proj":"Home","icon":"thermostat","fw":"1.2.0",
      "auth":"none|pin","ok":true|false,"nonce":"<16 hex bytes, only when ok:false>","caps":["wifi","ota","chart","ble","ntp","ntfy"]}
C→D  {"t":"auth","mac":"<hex HMAC-SHA256(key=pin, msg=nonce+id)>"}   # only when ok:false and auth:pin
D→C  {"t":"auth","ok":true,"tok":"<32 hex>"}                             # token persisted in NVS, client stores it
C→D  {"t":"time","unix":1728700000,"tz":120}                             # client clock, sent right after a successful hello
```
- PIN never travels in clear: device issues a fresh nonce per hello, client proves knowledge of the PIN with HMAC-SHA256 (mbedtls, already in the core). Replay is useless because the nonce changes.
- Token = 16 random bytes, generated on first successful auth, revocable via `{"t":"sys","cmd":"revoke"}`.
- 5 wrong attempts → 60 s lockout. Token never expires unless revoked or PIN changed.
- `time`: device adopts the client clock when it has no better source (NTP, RTC). `tz` = minutes east of UTC, used for the `clock` widget and log timestamps.
- `proj` (project/group name), `icon` (named icon) and `fw` feed the device list in the clients.
- No TLS. Documented threat model: trusted local network only.

### 3.2 UI description
```
D→C  {"t":"ui","rev":7,"w":[ {widget}, ... ]}
```
Widget object: `{"id":"temp","ty":"gauge","lbl":"Temp","min":0,"max":100,"unit":"°C","grp":"Sensors","ro":true}`.
Sent after successful hello and whenever the device calls `ui.rebuild()`. `rev` lets clients skip unchanged UI.

Common props on every widget: `id`, `ty`, `lbl`, `grp` (group card), `page`, `row`, `size` (relative width in a row, optional fixed height px), `sq` (square aspect), `dis` (disabled), `hint` (help text on long-press/hover), `icon` (named icon from a fixed set shipped with both renderers, Material Symbols subset), `ro`.

Widget types v1:
| ty | props | value |
|---|---|---|
| `label` | lbl, unit, fmt | string/number |
| `button` | lbl, color, hold (momentary: reports press and release) | event only (`ev` with `v`:1/0 when `hold`) |
| `switch` | lbl, icon (icon-only when no lbl), on, off (state labels) | bool |
| `slider` | lbl, min, max, step, unit | number |
| `number` | lbl, min, max, step, unit, spin (render +/- buttons) | number |
| `text` | lbl, maxlen, secret, re (regex validated client-side) | string |
| `textarea` | lbl, maxlen, rows | string |
| `select` | lbl, opts[], style: list\|seg (dropdown or segmented buttons) | index |
| `flags` | lbl, opts[] | bitmask (uint32) |
| `color` | lbl | uint32 RGB |
| `datetime` | lbl, mode: date\|time\|datetime | unix seconds |
| `joystick` | lbl, center (auto-return), exp | [x,y] each -100..100 |
| `dpad` | lbl | event: `ev` with `v`: "u"\|"d"\|"l"\|"r"\|"c" on press, 0 on release |
| `gauge` | lbl, min, max, unit, zones[], style: arc\|round\|linear | number |
| `progress` | lbl, min, max, center (bipolar bar from the middle) | number |
| `display` | lbl, digits, unit | number/string (7-segment style readout) |
| `led` | lbl, color, icon, rgb (value is a color) | bool, or uint32 RGB when `rgb` |
| `chart` | lbl, series[{id,lbl,color}], win (seconds), unit, style: line\|bar\|area, legend, vals (show current values) | pushed points |
| `log` | lbl, rows, cap (client ring buffer lines) | pushed lines via `log` message; device replays `ESPFACE_LOG_HISTORY` lines on connect |
| `table` | lbl, cols[{lbl,w,align}] | array of rows, each an array of cells |
| `image` | lbl, src (URL) | – (src changeable via `prop`) |
| `stream` | lbl, src (MJPEG URL) | – |
| `clock` | lbl, fmt | unix seconds pushed; client ticks locally |
| `map` | lbl, zoom | pushed points [[lat,lon,lbl]] (phase 8, online tiles) |
| `header` | lbl | – |
| `textblock` | lbl, text (static multi-line paragraph, e.g. instructions) | – |
| `group` | lbl, fold (collapsible, default open; state client-side) | – (widgets reference it via `grp`) |
| `page` | lbl, icon | – (widgets reference it via `page`; renderer shows tabs or bottom nav) |
| `row` | – | – (widgets reference it via `row`, laid out side by side by `size`) |
| `spacer` | size | – |

Layout: pages → group cards → rows → widgets, all in declaration order. Widgets without `page` go to the first page; without `row` they take the full card width. No absolute coordinates. Page, fold and scroll state live only in the client, never on the device.

### 3.3 Values and events
```
D→C  {"t":"upd","v":{"temp":21.5,"pump":true}}          # batched, coalesced every ≥100 ms
C→D  {"t":"set","id":"pump","v":true}                    # device acks via upd (echo)
C→D  {"t":"ev","id":"reboot_btn"}                        # button press; hold buttons and dpad add "v"
D→C  {"t":"pts","id":"chart1","s":"temp","p":[[1728700000123,21.5],...]}  # chart points, ts in ms epoch or uptime ms
D→C  {"t":"toast","lvl":"info|warn|err","msg":"..."}
D→C  {"t":"log","msg":"...","id":"term","c":"#f00"}      # device log stream; optional target log widget and line color
D→C  {"t":"prop","id":"temp","p":{"lbl":"Boiler temp","max":150,"dis":true,"vis":false,"src":"..."}}  # runtime prop change, no rebuild
D→C  {"t":"dlg","id":"d1","kind":"confirm|prompt","msg":"Erase all?","def":""}   # device-initiated dialog
C→D  {"t":"dlg","id":"d1","ok":true,"v":"typed text"}                           # answer (v only for prompt)
C→D  {"t":"page","id":"setup"}                                                  # client's active page
```
- `prop` merges into the client's widget model without a `rev` bump. `vis:false` hides a widget. The firmware keeps mutable props in its registry so a later `ui` resend is consistent.
- Dialogs are not widgets: the device opens one on all connected clients; the first answer wins, the others are dismissed.
- Charts: client keeps the ring buffer (window `win`). Device keeps nothing, except an optional small history (`ESPFACE_CHART_HISTORY` points) replayed on connect.
- Log widgets work like charts: client-side ring buffer of `cap` lines; the device optionally keeps the last `ESPFACE_LOG_HISTORY` lines per log widget and replays them on connect.
- `page`: the device skips `upd` values for widgets on other pages for that client and sends a full `upd` of the new page on switch. `pts` and `log` are always pushed so client ring buffers stay continuous.

### 3.4 System pages (capability-gated)
```
{"t":"sys","cmd":"info"}        → {"t":"sys","cmd":"info","chip":"ESP32-S3","fw":"1.2.0","repo":"owner/repo","about":"...","rr":"ota|button|panic|power|wdt","heap":..,"up":..,"ip":..,"rssi":..,"time":..}
{"t":"sys","cmd":"wifi.scan"}   → {"t":"sys","cmd":"wifi.scan","ap":[{"ssid":..,"rssi":..,"enc":true}]}
{"t":"sys","cmd":"wifi.set","ssid":..,"pass":..}  → status pushes {"t":"sys","cmd":"wifi.status",...}
{"t":"sys","cmd":"reboot"}
{"t":"sys","cmd":"pin.set","pin":"..."}  / "revoke"
{"t":"sys","cmd":"ota.begin","size":N,"md5":".."}  then binary chunks (WS binary frames) → {"t":"sys","cmd":"ota.progress","pct":..} → "ota.done"
{"t":"sys","cmd":"ota.url","url":"https://..."}    → device downloads itself, same progress pushes
```
- `rr` = last reboot reason from `esp_reset_reason()`, mapped to a short string.
- `repo` (optional, set by the sketch) lets clients check GitHub releases for a newer version and offer `ota.url` with the release asset. The check is user-triggered and needs internet; it is off by default in the app to keep it offline-by-design.
- OTA over WiFi uses WS binary frames (or `POST /update` multipart as a fallback for browsers). OTA over BLE and streams: not in v1, clients grey it out; `ota.url` works on any transport as long as the device has WiFi.

### 3.5 BLE mapping
- Service UUID `0000ea00-...` (fixed, used for discovery filter), characteristics: RX (write, no response), TX (notify), plus a read-only "name/id" characteristic for the scanner list.
- Framing: `[seq:1][flags:1 (bit0=last)][payload]` chunks up to MTU−3 (request MTU 512); messages reassembled by seq. No compression in v1.
- Same JSON messages; the `ui` message can be several KB, so the device sends it chunked; clients show "loading" progress.

### 3.6 Stream mapping (UART, USB CDC, Bluetooth Classic SPP)
- One JSON message per line, terminated by `\n`; messages are newline-free by spec, so no escaping is needed.
- No binary frames: OTA push is unavailable, `ota.url` still works.
- One client per stream; the session/token logic is identical to WS.
- Android reaches these via USB OTG (`usb_serial`) and Bluetooth Classic (`flutter_bluetooth_serial`); iOS has neither. No discovery: the app lists serial ports / paired devices.

### 3.7 Discovery
- WiFi: mDNS service `_espface._tcp`, TXT `id`, `name`, `v`, `proj`, `icon`. Plus manual IP/host entry and QR code (`espface://<host>?id=..&name=..`) that the device can expose via web page / serial print.
- BLE: advertise service UUID + device name.
- Captive AP: default SSID `espFace-<id>`, no password by default (configurable), DNS catch-all.

Versioning: `v` in hello. Clients support ≥ their own major; unknown widget types render as a label "unsupported widget" rather than failing; unknown keys and message types are ignored.

## 4. Firmware library (firmware/)

### 4.1 Constraints
- Zero mandatory external dependencies besides ArduinoJson 7 (ubiquitous, header only).
- HTTP + WebSocket via ESP-IDF `esp_http_server` (bundled with Arduino core 3.x, supports WS) – avoids ESPAsyncWebServer fork chaos.
- BLE via NimBLE-Arduino (optional, `#define ESPFACE_BLE` or PlatformIO flag), because Bluedroid costs ~100 KB more RAM. Bluetooth Classic SPP (`ESPFACE_BT_CLASSIC`, classic ESP32 only) needs Bluedroid and is therefore mutually exclusive with NimBLE in one build.
- Target footprint: < 20 KB RAM steady state without BLE for the base widget set, < 90 KB flash without embedded web, single FreeRTOS task for networking; user code calls `face.loop()` or we run our own task (configurable). `ESPFACE_MAX_CLIENTS` (default 4) and `ESPFACE_LOG_HISTORY` (default 0) are compile-time. Mutable props (`lbl`, `src`) cost RAM only when the sketch changes them at runtime.
- Works with existing sketches that already run their own web server on port 80: espFace port configurable (default 80, falls back to 8080 if bind fails and logs).

### 4.2 Public API (header `espFace.h`)
```cpp
EspFace face;

void setup() {
  face.begin("Boiler");                      // mDNS name, AP SSID derived, NVS namespace "espface"
  face.setProject("Home").setIcon("thermostat").setVersion("1.2.0").setRepo("owner/repo").setAbout("Boiler controller");
  face.setPin("1234");                        // optional; or face.setPin(nullptr) disables
  face.wifi().autoConnect();                  // tries NVS creds, else starts captive AP
  face.enableOta(true);
  face.enableNtp(true);                       // optional; otherwise the client clock is used
  face.ntfy("https://ntfy.sh", "boiler-alerts", token);   // optional direct ntfy, HTTP POST from the device
  face.serial(Serial);                        // any Stream as transport (UART, USB CDC, BluetoothSerial)
  face.onConnect([](Client& c){ ... });       // per client; face.onDisconnect(...), face.clients() count
  face.onReboot([](RebootReason r){ saveState(); });   // before a client- or OTA-triggered reboot

  auto& ui = face.ui();
  ui.page("main", "Boiler").icon("home");
  ui.header("Boiler");
  ui.gauge("temp", "Temperature", 0, 120, "°C").style(Gauge::Round).group("Sensors");
  ui.chart("tchart", "Temp history", 600).series("temp", "Temp").group("Sensors");
  ui.row("r1").group("Control");
  ui.sw("pump", "Pump").row("r1").size(1).onChange([](bool v){ digitalWrite(PUMP, v); });
  ui.slider("target", "Target", 20, 90, 1, "°C").row("r1").size(3).persist().onChange([](float v){ target = v; });
  ui.button("reset", "Reset error").hint("Clears the error latch").onClick([]{ err = 0; });
  ui.joystick("joy").center(true).onChange([](int x, int y){ ... });
  ui.log("term", "Log", 200);
  ui.page("setup", "Setup").icon("settings");
  ui.text("note", "Note", 32).page("setup").regex("^[A-Za-z ]*$").onChange([](const String& s){ ... });
}

void loop() {
  face.loop();                                // or face.beginTask() in setup() to run on own task
  face.delay(50);                             // delay that keeps pumping the network loop
  if (every(1000)) { face.set("temp", t); face.push("tchart", "temp", t); }
  if (overheated) {
    ui.prop("temp").color("#f00").label("Temp (HOT)");       // runtime prop update, no rebuild
    ui.show("reset", true);
    ui.confirm("d1", "Shut down pump?", [](bool ok){ if (ok) digitalWrite(PUMP, 0); });
    face.notify("Boiler", "Overheated", Ntfy::High);        // direct ntfy, rate-limited (default 1 per 10 s)
    face.log("term", "overheat", "#f00");
  }
}
```
- Widgets stored in a static-ish vector of small structs (id as `const char*` or interned String, props packed); `ui` JSON is streamed to the socket, never fully buffered.
- Values are owned by the library (variant: bool/float/int/String), `face.set()` marks dirty, a 100 ms flush coalesces into one `upd`.
- `.persist()` stores the input value in NVS under the widget id on change (debounced) and restores it before `setup()` returns; `onChange` fires once with the restored value.
- Callbacks are `std::function`; a cheap `ESPFACE_NO_STD_FUNCTION` mode with plain function pointers for minimal builds (phase 2 or skip if footprint OK).
- Bind helpers: `ui.sw("pump","Pump").bind(pumpOn)` keeps a variable in sync both ways.
- Multiple UIs: `auto& setupUi = face.addUi("setup"); face.ble().use(setupUi);` binds a second, independent UI definition to a transport (e.g. a provisioning UI on BLE, the main UI on WiFi). Default: all transports serve `face.ui()`. Each UI can have its own PIN (`setupUi.pin(nullptr)` for an open setup UI, `face.setPin()` applies to the default UI).
- Time: `face.time()` returns unix seconds from NTP, else from the last client `time` message, else 0; `face.setTime()` for an external RTC.

### 4.3 Internal modules (src/)
```
EspFace.h/.cpp        facade, lifecycle, loop, task
ui/Widget.h, Ui.cpp    widget registry, builder, JSON streaming, mutable props, persist
proto/Codec.cpp        message parse/dispatch (ArduinoJson filters to keep RAM low)
proto/Session.cpp      per-client state, HMAC auth, lockout, token (NVS), dialogs
transport/Transport.h  interface: send(clientId, str), onMessage, broadcast, ui binding
transport/WsTransport  esp_http_server WS + static routes (/, /ws, /update, /r/* when embedded)
transport/BleTransport NimBLE GATT, chunking/reassembly
transport/StreamTransport  any Arduino Stream, line framing (UART, USB CDC, BluetoothSerial)
sys/WifiMgr.cpp        STA/AP, scan, NVS creds, captive DNS (DNSServer from core)
sys/Ota.cpp            Update.h, md5 verify, progress push, ota.url via HTTPClient
sys/Info.cpp           chip/heap/uptime/reset reason/version/repo
sys/Time.cpp           client clock, optional NTP (sntp from IDF)
sys/Ntfy.cpp           direct ntfy POST with rate limit
web/bootstrap.h        2 KB gzipped bootstrap HTML (generated)
web/embed.h            optional full renderer (generated by tools/embed-web.py)
```
Bootstrap page: loads `https://<RENDERER_HOST>/r/1/app.js` with a 5 s timeout; on failure shows "No internet – install the espFace app or flash with ESPFACE_EMBED_WEB" plus the device hostname. Host is a compile-time define with our default; users can point it to their own server.

### 4.4 Examples
`Minimal`, `FullDemo` (every widget), `ExistingWebServer` (shares port), `BleOnly`, `SerialOnly`, `EmbeddedWeb`, `Provisioning` (setup UI on BLE via `addUi`), `Notify` (ntfy).

### 4.5 Tests
- PlatformIO `native` env: unit tests for Codec, Ui JSON output, Session auth state machine (HMAC, lockout), persist, BLE chunker, stream framing, against `protocol/vectors`.
- `esp32dev` and `esp32-s3` CI build matrix (GitHub/Forgejo Actions in a PlatformIO Docker image) for all examples with/without BLE, BT classic and embed flags; report flash/RAM in CI to catch footprint regressions.

## 5. Web renderer (web/)

- Vite + Preact + TypeScript, target < 80 KB gzipped incl. uPlot for charts. No framework CSS; small hand-written stylesheet, light/dark via `prefers-color-scheme`, user theme settings (accent color, font scale, wide mode) in `localStorage`.
- Single `app.js` + `app.css`, loaded by the bootstrap page or served embedded from `/r/1/`.
- Connects to `ws://<location.host>/ws` (or `?host=` param for dev against fake device).
- Modules: `transport/ws.ts`, `proto/` (types generated from protocol JSON schema via `json-schema-to-typescript`), `store.ts` (values, ui rev, chart and log ring buffers, prop merges, page state), `widgets/*.tsx` one per type, `pages/` (main with page tabs, WiFi, OTA via `POST /update` multipart or `ota.url`, info incl. reboot reason and release check, pairing PIN dialog, device dialogs).
- Icons: Material Symbols subset as inline SVG sprite, same names as the Flutter app.
- Token persisted in `localStorage` keyed by device id.
- `/r/1/flash`: WebSerial flashing page (esptool-js) for blank ESPs, hosted site only (secure context required), fed by a GitHub release or a local `.bin`. Not embedded.
- Hosting: static site on Coolify at `https://<renderer-host>/r/<major>/…` with immutable caching and CORS `*`. Breaking renderer changes bump the major path so old firmware keeps working.
- Build runs in Docker (`docker/web.Dockerfile`), output also consumed by `firmware/tools/embed-web.py`.
- Tests: Vitest for store/codec against protocol vectors; Playwright smoke test against the fake device.

## 6. Flutter app (apps/mobile/)

### 6.1 Stack
- Flutter stable, Dart 3; Riverpod (state), go_router, `web_socket_channel`, `flutter_blue_plus` (BLE), `flutter_bluetooth_serial` (BT Classic, Android), `usb_serial` (USB OTG, Android), `nsd` (mDNS, Android+iOS), `fl_chart`, `flutter_map` (map widget, online tiles), `drift` or `shared_preferences`+`flutter_secure_storage` (device list + tokens), `mobile_scanner` (QR), `file_picker` (OTA .bin).
- No Firebase/Google services → F-Droid buildable; Play variant identical.
- iOS: Info.plist entries for local network (`NSLocalNetworkUsageDescription`, Bonjour service `_espface._tcp`), Bluetooth usage descriptions; build/sign needs a Mac.

### 6.2 Architecture
```
lib/
  core/transport/      Transport (abstract): WsTransport, BleTransport, StreamTransport (USB, BT classic) – same message stream API
  core/proto/          message models (generated via json_serializable from schema), codec
  core/session/        hello/auth (HMAC) flow, token store, clock message, reconnect/backoff
  features/devices/    device list grouped by proj, drag-to-reorder, icons, discovery (mDNS + BLE scan + serial ports), manual add, QR scan
  features/render/     UiModel → widget tree; one Flutter widget per `ty`; pages, rows, fold state; value store; chart/log buffers; prop merges; dialogs
  features/system/     info (version, about, reboot reason), WiFi provisioning, OTA (push or URL), optional release check, PIN management
  app/                 routing, theme (Material 3, dynamic color, user accent/font/wide settings), settings, white-label config
```
- Renderer is purely data-driven: `ui` message → immutable model → pages of `ListView`s of group cards; `upd` → per-widget `ValueNotifier`s so only touched widgets rebuild; `prop` patches the model in place.
- Transport selection per saved device: prefer WiFi when reachable, fall back to BLE, then serial; user can pin one.
- Offline by design: nothing is fetched from the internet except the user-triggered release check and map tiles.
- White-label: a build flavor driven by `--dart-define` (app name, logo, colors, optional fixed `proj` filter, optional locked device list) so a product vendor can ship a branded build without forking.

### 6.3 Tests
- Unit: codec, session state machine, chunker and stream framing against protocol vectors.
- Widget tests for each renderer widget.
- Integration test against the fake device (WS) on CI; BLE, USB and BT classic tested manually on hardware.

## 7. Fake device (tools/fake-device/)
Node + `ws` implementing the device side of the protocol with a demo UI using every widget, pages and rows, simulated sensor data, HMAC PIN auth, chart and log streams, dialogs, prop updates, fake WiFi scan and OTA. Used by web and app dev and CI. Also useful as the reference implementation while the firmware is being written.

## 8. Phases and deliverables

| Phase | Deliverable | Depends on |
|---|---|---|
| 0 Protocol (done 2026-10-13) | `PROTOCOL.md`, JSON schema v1 incl. all widget types, `prop`, `dlg`, `time`, HMAC auth; test vectors; fake device | – |
| 1 Firmware core (done 2026-10-13) | begin/loop, WS transport, UI builder with pages/rows/groups, upd/set/ev, HMAC PIN auth (per UI), persist, prop/show-hide, dialogs, client clock, active-page filtering, multiple UIs, connect/disconnect/reboot callbacks, `face.delay`, base widgets (label, button, switch, slider, number, text, select, gauge, progress, led, chart, header, group, page, row, spacer), captive AP + bootstrap page, `Minimal` + `FullDemo` examples, native tests, CI footprint report | 0 |
| 1b Firmware extended widgets (done 2026-10-13) | textarea, flags, color, datetime, joystick (`onMove`), dpad, hold button, spin, regex, display, log (+history replay), table (`setRows`), image, stream, clock (device time pushed every minute), map (`setPoints`), textblock, gauge styles, chart styles/legend, switch labels, segmented select, RGB led, bipolar progress, icons; `FullDemo` I/O page, native tests, schema-checked output | 1 |
| 2 Web renderer | all widgets, pages, rows, dialogs, prop merges, pairing dialog, charts/logs, theme settings, hosting on Coolify, embed tooling + `EmbeddedWeb` example | 0 (dev against fake device), 1 for e2e |
| 3 App WiFi | Flutter app: discovery, pairing, renderer for all widgets, pages, dialogs, charts/logs, device groups and icons, theme settings, white-label flavor; Android debug builds in Docker | 0 |
| 4 System pages | WiFi provisioning, OTA push + `ota.url`, info with version/about/reboot reason, optional GitHub release check, NTP helper, direct ntfy, reboot, PIN change in firmware + web + app; WebSerial flash page on the hosted site | 1,2,3 |
| 5 BLE + streams | NimBLE transport + chunking, StreamTransport (UART/USB CDC/BluetoothSerial) in firmware; BLE, USB OTG and BT Classic transports in app; `BleOnly`, `SerialOnly`, `Provisioning` examples | 1,3 |
| 6 Hardening | reconnect/backoff, multi-client, RAM soak tests, S2/S3/C3/C6 matrix, docs site, API reference | 1–5 |
| 7 Release | Arduino Library Manager + PlatformIO registry submission, F-Droid via existing flow, Play Store, App Store (Mac needed), renderer v1 frozen at `/r/1/` | 6 |
| 8 Relay | `RelayTransport` (device outbound WS, client sessions multiplexed by a session id at the transport layer), relay server as a self-hostable Docker image plus a public instance run by us, admin page with device token management, online state and connection statistics, `map` widget | 7 |

Rough effort (one developer): 0: 1.5 wk · 1: 4 wk · 1b: 2 wk · 2: 3 wk · 3: 4 wk · 4: 3 wk · 5: 3 wk · 6: 2 wk · 7: 1–2 wk ≈ 6 months; 8: +3 wk afterwards.
Phases 2 and 3 can run in parallel with 1 thanks to the fake device.

## 9. Risks and mitigations
- **RAM on classic ESP32 with WiFi+BLE both on**: coexistence eats ~50 KB; document "BLE+WiFi simultaneously needs ≥ 100 KB free heap", default BLE off, allow BLE-only mode with WiFi off. Bluetooth Classic adds Bluedroid (~100 KB more) and excludes NimBLE in the same build; document it as "SPP or BLE, not both".
- **Widget count vs. footprint**: 30 widget types in three renderers is the main scope risk. Base set ships in phase 1; extended set is a separate phase with its own CI footprint gate so a bloated widget cannot slip in unnoticed.
- **esp_http_server WS limitations** (one frame at a time, 4 KB default buffers): stream the `ui` message in multiple frames; raise `max_open_sockets`; cap clients at `ESPFACE_MAX_CLIENTS` (default 4).
- **iOS local-network and BLE permissions**: handle denial UX explicitly; mDNS on iOS requires Bonjour services listed in Info.plist. USB OTG and BT Classic are Android-only; the app hides them on iOS.
- **Captive portal detection** differs per OS: answer `/generate_204`, `/hotspot-detect.html`, `/connecttest.txt`, `/ncsi.txt` with the bootstrap page; Android may still need a “sign in” tap.
- **Renderer loaded from the internet while connected to the ESP AP**: phones usually drop or deprioritise an AP without internet; document that the captive flow is primarily a “get credentials in” path and the apps are the primary UI. Embed flag fixes it for products.
- **WebSerial** works only in Chromium browsers over https; the flash page is a convenience, not a requirement.
- **Release check and map tiles need internet**: both are opt-in and user-triggered so the offline guarantee of the app holds by default.
- **Schema drift between three renderers**: protocol vectors are the contract; CI in all three repos runs them.
- **Cloud relay later**: Transport abstraction on both ends + device `id` + token design are relay-compatible; relay will add a `RelayTransport` without protocol changes.

## 10. Open items to settle before coding
1. Renderer host domain and whether the Coolify static site already exists.
2. Decided 2026-10-12: MIT for everything; app id `dev.manzari.espFace`.
3. Arduino library name on the registry (`espFace` must be unique; check Library Manager index).
4. Who owns Apple developer account / Mac for iOS builds.
5. NVS layout for `persist()` values (namespace per UI, key = widget id, 15-char NVS key limit vs. widget ids).
6. Decided 2026-10-12: ntfy is device-direct only; the relay does not forward notifications.
7. Icon set: exact Material Symbols subset shared by web and Flutter, and how a sketch references icons not in the subset (fallback glyph).
