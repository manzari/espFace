# FAQ and troubleshooting

## The captive portal does not open or the UI stays blank

- The device answers the OS detection URLs (`/generate_204`, `/hotspot-detect.html`, `/connecttest.txt`, `/ncsi.txt`) with the bootstrap page. Android may still need a tap on the "Sign in to network" notification.
- Phones tend to drop or deprioritise a WiFi network without internet. The captive flow is mainly for getting WiFi credentials in; the app is the primary UI.
- The device serves the renderer itself, so no internet is needed. Firmware 1.0.0 loaded it from the renderer host instead; update the library if the page shows "No internet".

## iOS cannot find my device

Allow the local network permission when iOS asks, or enable it in Settings > espFace. mDNS discovery needs the Bonjour service `_espface._tcp`, which the app declares. USB and Bluetooth Classic do not exist on iOS.

## Crashes, resets or low memory with BLE and WiFi

BLE together with WiFi on a classic ESP32 wants 100 KB of free heap or more. Reduce the UI, drop other libraries, or run a BLE-only build (`face.enableWs(false)`, no WiFi). Bluetooth Classic SPP and BLE are mutually exclusive in one build, since Bluedroid and NimBLE cannot coexist.

## How big is it?

On esp32dev, relative to `Minimal`: a stream transport adds about 28 KB flash and no static RAM (2 KB heap per instance), NimBLE adds about 11 KB static RAM and 270 KB flash, Bluedroid SPP about 14 KB static RAM and 755 KB flash. The TLS client costs about 120 KB flash and HTTPClient plus Update about 60 KB, both linked only when you call `enableOta()` or `ntfy()`.

## "Device is full" or err 9

The device keeps at most `ESPFACE_MAX_CLIENTS` sessions (default 4). A fifth client gets err 9 and is closed; clients show "Device is full (too many clients), retrying" and keep trying. Stale sessions from phones that left without closing free up when the transport notices the drop. Raise the limit with `-DESPFACE_MAX_CLIENTS=6` if RAM allows. A second OTA while one runs is also err 9.

## The PIN dialog keeps coming back

The stored token no longer matches: someone revoked all tokens, or changed the PIN (`pin.set`). Enter the PIN again. If the dialog keeps rejecting a correct PIN, check that the sketch's `setPin` value is what you type; note that `setPin` for a second UI may differ (`ui.pin(..)`).

## Locked out

Five wrong PINs lock the device for 60 seconds. The dialog shows a countdown. Wait for it to run out, then enter the correct PIN.

## Port 80 is taken

Another server on the device owns port 80. Call `face.setPort(8080)` before `begin()`, or rely on the automatic fallback to 8080 when binding port 80 fails (logged). Pass `host:8080` to the app or the `/connect/?host=` page.

## The flash page does not work

WebSerial exists only in Chromium browsers (Chrome, Edge) and needs https. The page loads esptool-js from jsdelivr, so it needs internet. It is a convenience; use the Arduino IDE or `pio run -t upload` otherwise.

## The release check fails

It is opt-in and user-triggered, queries GitHub and needs internet on the client. The device needs internet too when you install the asset through `ota.url`. The sketch must call `setRepo("owner/repo")` and `setVersion(..)`.

## ArduinoJson errors at compile time

espFace needs ArduinoJson 7. Version 6 has a different API and fails to compile. Update the library in the Library Manager or pin `bblanchon/ArduinoJson@^7.0.0` in PlatformIO.

## My UI is rejected or truncated

The `ui` message is capped at 500 widgets (`ui.w` in the schema). Spread large UIs over fewer widgets, use tables and logs, or generate sections as needed and call `rebuild()`.

## A big UI is slow over BLE

The `ui` message is chunked into MTU-sized packets, so a large UI takes a while. The app shows a progress chip while it arrives. Keep BLE UIs small (a setup UI is a good fit) and put big dashboards on WiFi.

## Persist does not work

`.persist()` uses the widget id as the NVS key, which allows 15 characters at most. Longer ids are rejected by the protocol anyway (`^[A-Za-z0-9_]{1,15}$`). Persisted values are restored before `setup()` returns. They live in the NVS namespace of their UI (`efv_<ui name>`), so renaming a UI with `addUi()` drops its saved values.
