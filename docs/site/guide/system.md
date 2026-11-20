# System features

System features are gated by capabilities. The device announces them in its `hello` (`caps`), and the clients show the matching pages (info, WiFi, security, OTA, console) only when present. A command without its capability is answered with err 8.

| Capability | Enabled by |
|---|---|
| `wifi` | `face.wifi().autoConnect()` |
| `ota`, `otaurl` | `face.enableOta(true)` |
| `ntp` | `face.enableNtp(true, ...)` |
| `ntfy` | `face.ntfy(...)` |
| `pin` | `face.setPin(...)` |
| `info`, `reboot` | on by default |
| `ble` | `face.ble()` |

A capability can be withdrawn at runtime with `face.core().removeCap("pin")` (also `reboot`, `wifi`) and restored with `addCap`; `face.enableOta(false)` withdraws `ota` and `otaurl` and makes `POST /update` answer 404. While a capability is missing its commands are answered with err 8 and the clients hide the page. A device that must refuse reconfiguration in some state (a time lock, a running batch) uses this together with `prop(id).disabled(true)`, which the core enforces on incoming `set` messages.

## WiFi provisioning

```cpp
face.wifi().autoConnect();                 // stored credentials, else captive AP
// face.wifi().connect("ssid", "pass");    // store credentials from the sketch
```

- With stored credentials the device joins that network. Without them, or when joining fails, it starts the access point `espFace-<id>` with a captive portal. The portal answers the OS detection URLs (`/generate_204`, `/hotspot-detect.html`, `/connecttest.txt`, `/ncsi.txt`) with the bootstrap page.
- Clients use `sys wifi.scan` (asynchronous, deduplicated, sorted by RSSI) and `sys wifi.set` (stores the credentials). The device then pushes `wifi.status` with `connecting`, `connected`, `failed` or `ap`. The AP stays up during the attempt and the device falls back to AP mode on failure. `wifi.status` can also be requested.
- After joining, the device advertises itself over mDNS as `_espface._tcp`, which is what the app discovers.
- A UI that only has widgets can do the same with its own scan and connect widgets; the `Provisioning` example does this over BLE.

## OTA updates

```cpp
face.enableOta(true);
// face.setOtaCaCert(pem);   // verify https downloads
```

Three ways in, all gated by `ota` and `otaurl`:

1. **Push over WebSocket.** The client sends `ota.begin` with size and MD5, then binary frames of up to 4096 bytes. The device writes them, pushes `ota.progress` at most every 500 ms, verifies the MD5, answers `ota.done` and reboots after 1 s. One OTA at a time; a second `ota.begin` is err 9. Push is WebSocket only: BLE and stream sessions get err 8 and can use `ota.url`.
2. **By URL.** `sys ota.url` with an http or https URL the device can reach. The download runs inside `face.loop()`, so clients receive progress pushes but other traffic waits until it finishes.
3. **`POST /update`.** Raw body or multipart. With a PIN set, send a valid session token as `?tok=<token>` or as `Authorization: Bearer <token>`.

Notes:

- Without `setOtaCaCert()`, https downloads and ntfy use unverified TLS.
- `-DESPFACE_NO_TLS` drops TLS entirely; https URLs then fail with a log line. The TLS client costs about 120 KB of flash, HTTPClient plus Update about 60 KB. Both are linked only when the sketch calls `enableOta()` or `ntfy()`.
- OTA is off by default and must be enabled explicitly in the sketch.

## NTP

```cpp
face.enableNtp(true, "pool.ntp.org", "CET-1CEST,M3.5.0,M10.5.0/3");
```

Uses IDF SNTP and rechecks every 10 minutes. The timezone is a POSIX TZ string or `nullptr`. The system time feeds `face.time()` and the clock widgets. Without NTP the device falls back to the clock a client sends in its `time` message.

## ntfy notifications

```cpp
face.ntfy("https://ntfy.sh", "boiler-alerts");           // optional third argument: token
face.notify("Boiler", "Overheated", Ntfy::High);
face.ntfyRateLimit(30000);
```

The device POSTs directly to the ntfy server, one FreeRTOS task per message, so `loop()` never blocks. The default rate limit is one message per 10 s. A queue of 4 holds pending messages and `notify()` returns false when it is full.

## Info page

`face.setVersion("1.0.0").setRepo("owner/repo").setAbout("text")` fills the info page together with chip, heap, uptime, IP, SSID, RSSI, MAC, client count and the reset reason (`ota`, `button`, `panic`, `power`, `wdt`, `sw`, `brownout`, `other`). An OTA reboot leaves a marker in NVS so it reads `ota`.

When a repo is set, the info card offers a release check. It is opt-in and only runs when the user presses the button: the client asks GitHub for the latest release, compares the tag with `fw` and offers the first `.bin` asset through `ota.url`. It needs internet on the client and on the device.

## Reboot

```cpp
face.onReboot([](RebootReason) { saveState(); });
face.reboot();                 // optional delay in ms, default 500
```

A client `sys reboot` is answered with `ok:true` and the device reboots after 500 ms. `onReboot` runs before any client-, OTA- or sketch-triggered reboot. `face.resetReason()` returns the reason for the last boot.

## PIN change and revoke

Clients with the `pin` capability can change the PIN (`pin.set`, 4 to 32 characters, empty disables it) and revoke all tokens (`revoke`). Both delete every stored token and drop the other sessions. See [Security model](/guide/security).

## Flash page

The renderer host has a WebSerial page at [r.espface.manzari.dev/flash/](https://r.espface.manzari.dev/flash/) that writes a `.bin` to a connected board with esptool-js and offers a serial monitor. It works in Chromium browsers over https only and is a convenience, not a requirement.
