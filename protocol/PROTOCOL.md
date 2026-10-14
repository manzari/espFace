# espFace protocol v1

Status: draft, phase 0 (2026-10-13). This file, `schema/v1/*.json` and `vectors/*.json` are the contract for the firmware, the web renderer and the apps.

## 1. Conventions

- Every message is one JSON object, UTF-8, without newlines. Clients and devices never send pretty-printed JSON.
- Every message has `"t"` (type). Direction is written C→D (client to device) or D→C (device to client).
- Keys are short on purpose. Unknown keys, unknown message types and unknown widget types are ignored by every side; a renderer shows an unknown widget as a placeholder labelled "unsupported widget".
- Numbers are JSON numbers. Booleans are JSON booleans. Colors are strings `#rrggbb`. Unix times are seconds unless a field says milliseconds.
- Identifiers (`id` of widgets, pages, rows, groups, dialogs) match `^[A-Za-z0-9_]{1,15}$`. The 15-character limit lets a widget id double as an NVS key.
- Device id is 6 to 12 lowercase hex characters derived from the MAC.
- The device may send any D→C message at any time after a successful hello. Clients must tolerate messages for widgets they do not know.

## 2. Transports and framing

| Transport | Framing |
|---|---|
| WebSocket (`ws://<host>:<port>/ws`) | one message per text frame; binary frames carry OTA data only |
| BLE (service `0000ea00-0000-1000-8000-00805f9b34fb`) | RX characteristic `0000ea01-...` write without response (write with response also accepted), TX `0000ea02-...` notify, `0000ea03-...` read-only `name\0id`. Each GATT packet is `[seq:1][flags:1][payload]`, flags bit0 = last chunk of this message, bit1 = first chunk; payload up to MTU-3. See below. |
| Stream (UART, USB CDC, Bluetooth SPP) | one message per line, terminated by `\n`. Binary frames do not exist, so OTA push is unavailable. See below. |

Message size: a device accepts C→D messages up to 2048 bytes. D→C messages have no fixed limit, but the `ui` message is the only one expected to exceed 4 KB.

BLE details (firmware: NimBLE, `ESPFACE_BLE`):
- Advertising carries the 128-bit service UUID; the device name is in the scan response. Scanners filter on the service UUID and read `0000ea03-...` for `name` and `id` (UTF-8 `name`, one NUL byte, six-hex-digit `id`) without connecting a session.
- The client requests an MTU of 512 after connecting; the device accepts up to 512 (payload up to 509 bytes per packet). Both sides chunk against the negotiated MTU. The client must subscribe to TX notifications before sending `hello`; the device drops notifications to an unsubscribed client.
- `seq` is a per-connection, per-direction counter starting at 0, incremented per packet, wrapping 255 → 0. The receiver expects `seq == previous + 1`: a packet with the previous `seq` again is a duplicate and ignored, any other value is a gap that discards the partial message (the next packet with bit1 set starts fresh). A continuation packet without an open message is dropped. A message exceeding the receiver's limit is answered with `err` code 2 and its remaining chunks are skipped up to bit0.
- Several centrals may connect (firmware default 2); each connection is one session with its own counters.

Stream details (firmware: `face.serial(Stream)`, `ESPFACE_BT_CLASSIC`):
- `\r` is ignored, empty lines are ignored, a line longer than 2048 bytes is discarded and answered with `err` code 2.
- One session per stream. There is no link-level connect, so the session opens on the first line; a `hello` on an open session closes it and starts a fresh unauthenticated one. Bluetooth SPP closes the session when the link drops; a UART may be configured with an idle timeout.
- Clients must ignore lines that are not a JSON object (boot ROM output, library log lines).
- `ota.begin` on a stream or BLE session is answered with `err` code 8; `ota.url` works.

## 3. Session lifecycle

```
C→D hello            client identifies itself, offers a stored token
D→C hello            device identity, auth state; nonce when a PIN is required
C→D auth             only when hello returned ok:false and auth:"pin"
D→C auth             ok + token, or failure with attempts left / lockout
C→D time             client clock, sent once after ok
D→C ui               full UI description
D→C upd              all current values (one message, may be large)
...                  normal traffic
```

- A client that reconnects sends `hello` with its stored token; if the device answers `ok:true` the session is authenticated without a PIN.
- Any C→D message other than `hello` and `auth` before the session is authenticated is answered with `err` code 3 and dropped.
- The device keeps at most `ESPFACE_MAX_CLIENTS` sessions (default 4), counted across all transports. A fifth connection gets `err` code 9 (on a WebSocket right after the upgrade, on a stream on its first line) and is closed; a BLE central beyond the limit is disconnected without a message.
- A session that is not authenticated within 30 s of opening (`ESPFACE_AUTH_TIMEOUT_MS`) gets `err` code 3 (`ref:"hello"`) and is closed.
- The device detects a dead client by the transport (WS close, BLE disconnect). There is no application-level ping; WebSocket clients must answer WS ping control frames (browsers do this automatically), a WebSocket client that sends nothing for 60 s, pongs included, is closed.

### 3.1 Authentication

The device has `auth:"none"` or `auth:"pin"`. With a PIN:

1. D→C `hello` contains `ok:false` and a fresh random 16-byte `nonce` as 32 lowercase hex characters.
2. The client computes `mac = HMAC-SHA256(key = PIN as UTF-8 bytes, msg = nonce_hex + device_id)` where `nonce_hex` is the 32-character string exactly as received and `device_id` is the `id` from the same hello. `mac` is sent as 64 lowercase hex characters.
3. D→C `auth` with `ok:true` carries a 32-character hex session token. The client stores it per device id and sends it in future hellos.
4. A wrong `mac` returns `ok:false` with `left` (attempts remaining). After 5 wrong attempts the device returns `lock` (seconds remaining) and refuses `auth` for 60 s. A hello during lockout also carries `lock`.
5. Tokens never expire. `sys revoke` deletes all tokens; `sys pin.set` deletes all tokens and changes the PIN.

Test vector: PIN `1234`, nonce `00112233445566778899aabbccddeeff`, id `a1b2c3` → mac `03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8`.

A device without a PIN answers `ok:true` to every hello and never sends `nonce`; the token field in that case is absent and clients send no token.

### 3.2 Time

After a successful hello the client sends `time` with its unix clock and timezone offset. The device uses it when it has no NTP or RTC. Timestamps in `pts` and `log` are milliseconds. A value below 2^40 is device uptime in milliseconds; the client converts it to wall time as `wall = hello_received_at + (ts - up)` using `up` from the device hello. A value of 2^40 or above is unix milliseconds.

## 4. Messages

### 4.1 hello

C→D
| field | type | notes |
|---|---|---|
| `v` | int | protocol major version the client speaks (1) |
| `client` | `"app"` \| `"web"` | |
| `tok` | string | optional stored token |

D→C
| field | type | notes |
|---|---|---|
| `v` | int | protocol major version of the device (1) |
| `name` | string | display name |
| `id` | string | device id |
| `proj` | string | optional project/group name |
| `icon` | string | optional icon name |
| `fw` | string | optional firmware version |
| `auth` | `"none"` \| `"pin"` | |
| `ok` | bool | session authenticated |
| `nonce` | string | 32 hex, only when `ok:false` and not locked |
| `lock` | int | seconds of lockout remaining, only when locked |
| `up` | int | device uptime in ms at the time of this message |
| `caps` | string[] | subset of `wifi`, `ota`, `otaurl`, `chart`, `ble`, `ntp`, `ntfy`, `pin`, `reboot`, `info` |

### 4.2 auth

C→D `{"t":"auth","mac":"<64 hex>"}`
D→C `{"t":"auth","ok":true,"tok":"<32 hex>"}` or `{"t":"auth","ok":false,"left":3}` or `{"t":"auth","ok":false,"lock":57}`

### 4.3 time

C→D `{"t":"time","unix":1728700000,"tz":120}`. `tz` is minutes east of UTC.

### 4.4 ui

D→C `{"t":"ui","rev":7,"w":[widget,...]}`. `rev` increments on every rebuild and persists across reboots when possible; a client with the same `rev` cached may skip parsing but must still apply the following `upd`. Widgets are rendered in array order. See section 5.

### 4.5 upd

D→C `{"t":"upd","v":{"<id>":value,...}}`. Values are batched, at most one message per 100 ms per client. A `set` is acknowledged by the echo of the value in the next `upd`, to the sender as well as to every other client on a page that shows the widget; there is no immediate reply. The first `upd` after `ui` contains every widget that has a value.

### 4.6 set

C→D `{"t":"set","id":"pump","v":true}`. Value types per widget are in section 5. The device validates range and type; invalid values are answered with `err` code 7 and the current value is re-sent in `upd`. `set` on a read-only (`ro`) widget is `err` code 7.

### 4.7 ev

C→D `{"t":"ev","id":"btn"}`. For `button` with `hold:true` and for `dpad`, `v` is present: `1` press / `0` release for buttons; `"u"|"d"|"l"|"r"|"c"` on press and `0` on release for dpad.

### 4.8 pts

D→C `{"t":"pts","id":"chart1","s":"temp","p":[[ts,value],...]}`. `s` is the series id. Points are ascending in time. The client keeps a ring buffer sized by the widget's `win`.

### 4.9 toast

D→C `{"t":"toast","lvl":"info|warn|err","msg":"..."}`. Transient, non-blocking.

### 4.10 log

D→C `{"t":"log","msg":"...","id":"term","c":"#ff0000","ts":12345}`. `id` targets a `log` widget; without `id` the line goes to the device console view. `c` and `ts` are optional.

### 4.11 prop

D→C `{"t":"prop","id":"temp","p":{...}}`. `p` contains any subset of the widget's props plus `vis` (bool). The client merges them into its widget model; `rev` does not change. Props that change the value type are not allowed.

### 4.12 dlg

D→C `{"t":"dlg","id":"d1","kind":"confirm|prompt","msg":"Erase all?","def":"","title":"..."}`
C→D `{"t":"dlg","id":"d1","ok":true,"v":"typed text"}` — `v` only for `prompt` with `ok:true`.

The device sends the dialog to every connected client of the UI that opened it; the first answer from any authenticated client of that UI is used, regardless of who saw it first, and the device sends `{"t":"dlg","id":"d1","close":true}` to all clients. Later answers and answers from clients of another UI get `err` code 6. A client that authenticates while a dialog is open receives it after `ui` and `upd`, with `timeout` set to the remaining seconds. A dialog without an answer is closed by the device after `timeout` seconds (default 60) and treated as `ok:false`.

### 4.13 page

C→D `{"t":"page","id":"setup"}`. Tells the device which page this client shows. The device may omit `upd` values for widgets on other pages for that client and sends a full `upd` of the page's widgets on every page change. `pts`, `log`, `toast`, `dlg` and `prop` are always sent.

### 4.14 sys

Both directions, `cmd` selects the operation. Each command requires the listed capability.

| cmd | cap | C→D | D→C |
|---|---|---|---|
| `info` | `info` | `{}` | `chip`, `fw`, `repo`, `about`, `rr` (`ota|button|panic|power|wdt|sw|brownout|other`), `heap`, `heapmin`, `up` (ms), `ip`, `ssid`, `rssi`, `mac`, `time` (unix s or 0), `clients` |
| `wifi.scan` | `wifi` | `{}` | `ap:[{ssid,rssi,enc}]` |
| `wifi.set` | `wifi` | `ssid`, `pass` | `wifi.status` pushes: `st` (`connecting|connected|failed|ap`), `ip`, `ssid`, `rssi` |
| `wifi.status` | `wifi` | `{}` | as above |
| `reboot` | `reboot` | `{}` | `ok:true`, then the device reboots after 500 ms |
| `pin.set` | `pin` | `pin` (4 to 32 chars, empty string disables) | `ok` |
| `revoke` | `pin` | `{}` | `ok` ; all tokens deleted, every other session is dropped |
| `ota.begin` | `ota` | `size`, `md5` (32 hex), `kind` (`fw` default) | `ok` ; then the client sends binary frames |
| `ota.progress` | `ota` | – | `pct` 0..100, pushed at most every 500 ms |
| `ota.done` | `ota` | – | `ok:true`, device reboots after 1 s; or `ok:false`, `msg` |
| `ota.abort` | `ota` | `{}` | `ok` |
| `ota.url` | `otaurl` | `url` (http or https) | same `ota.progress`/`ota.done` pushes |

OTA push: after `ota.begin` returns `ok:true` the client sends the image as WebSocket binary frames of up to 4096 bytes in order. The device writes them, pushes `ota.progress`, verifies the MD5 when `size` bytes arrived, and answers `ota.done`. Only one OTA at a time; a second `ota.begin` is `err` code 9. OTA push is WS-only; BLE and stream clients only get `ota.url`.

### 4.15 err

D→C `{"t":"err","code":3,"msg":"unauthorized","ref":"set"}`

| code | meaning |
|---|---|
| 1 | bad JSON or missing `t` |
| 2 | message too large |
| 3 | unauthorized (session not authenticated) |
| 4 | locked out |
| 5 | bad PIN |
| 6 | unknown widget / dialog id |
| 7 | bad value or read-only |
| 8 | capability not available |
| 9 | busy / too many clients |
| 10 | OTA failed |

`ref` is the `t` or `sys.cmd` of the offending message.

## 5. Widgets

### 5.1 Common props

| prop | type | meaning |
|---|---|---|
| `id` | string | required, unique within the UI |
| `ty` | string | required, widget type |
| `lbl` | string | label |
| `grp` | string | id of a `group` this widget belongs to |
| `page` | string | id of a `page`; absent = first page |
| `row` | string | id of a `row`; widgets in the same row sit side by side |
| `size` | number or [w, h] | relative width inside a row (default 1); `h` fixed height in px |
| `sq` | bool | square aspect |
| `dis` | bool | disabled |
| `vis` | bool | visible (default true; only meaningful via `prop`) |
| `hint` | string | help text on long-press / hover |
| `icon` | string | icon name from the shared set |
| `ro` | bool | read-only: rendered but not settable |
| `color` | string | accent color, only on types that list it |

Layout: pages → group cards → rows → widgets, in declaration order. A `group`, `page` or `row` widget must be declared before the widgets that reference it. Page, fold and scroll state live in the client.

### 5.2 Types

| ty | props | value in `upd` / `set` |
|---|---|---|
| `label` | `unit`, `fmt` (printf-style for numbers) | string or number |
| `button` | `color`, `hold` | none; `ev` |
| `switch` | `on`, `off` (state labels), `color` | bool |
| `slider` | `min`, `max`, `step`, `unit`, `color` | number |
| `number` | `min`, `max`, `step`, `unit`, `spin` | number |
| `text` | `maxlen`, `secret`, `re` | string |
| `textarea` | `maxlen`, `rows` | string |
| `select` | `opts` (string[]), `style` (`list`\|`seg`) | int index |
| `flags` | `opts` (string[], max 32) | int bitmask |
| `color` | – | int 0xRRGGBB |
| `datetime` | `mode` (`date`\|`time`\|`datetime`) | int unix seconds |
| `joystick` | `center` (auto-return), `exp` | [x, y], each -100..100 |
| `dpad` | – | none; `ev` with `v` |
| `gauge` | `min`, `max`, `unit`, `zones` ([{from,to,color}]), `style` (`arc`\|`round`\|`linear`) | number |
| `progress` | `min`, `max`, `center`, `color` | number |
| `display` | `digits`, `unit` | number or string |
| `led` | `color`, `rgb` | bool, or int 0xRRGGBB when `rgb` |
| `chart` | `series` ([{id,lbl,color}]), `win` (s), `unit`, `style` (`line`\|`bar`\|`area`), `legend`, `vals` | none; `pts` |
| `log` | `rows`, `cap` | none; `log` |
| `table` | `cols` ([{lbl,w,align}]) | array of rows, each an array of string/number cells |
| `image` | `src` | none |
| `stream` | `src` | none |
| `clock` | `fmt` | int unix seconds |
| `map` | `zoom` | array of [lat, lon, lbl] |
| `textblock` | `text` | none |
| `header` | – | none |
| `group` | `fold` | none |
| `page` | – | none |
| `row` | – | none |
| `spacer` | – | none |

Defaults: `min` 0, `max` 100, `step` 1, `win` 300, `rows` 5, `cap` 200, `digits` 4, `zoom` 12, `style` first listed value, `mode` `datetime`, `center` false, `fold` false, `legend` true, `vals` false.

## 6. Versioning

`v` in hello is the protocol major. A client supports a device whose major is less than or equal to its own. Additions within a major (new widget types, new props, new `sys` commands, new caps) are backwards compatible by the ignore-unknown rule. Removing or retyping a field requires a new major. The hosted web renderer lives at `/r/<major>/`.

## 7. Security model

No transport encryption. The protocol is meant for a trusted local network, BLE within reach, or a wired stream. The PIN never travels in clear (HMAC), but a session token does, and anyone on the network can read values and events in flight. Products that need more wrap the transport (VPN, the later relay over TLS) rather than the protocol.
