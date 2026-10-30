# Getting started

This page takes you from nothing to a working UI on your phone.

## Requirements

- An ESP32 board (ESP32, S2, S3, C3 or C6). ESP8266 is not supported.
- Arduino ESP32 core 3.x.
- ArduinoJson 7.

## Install with the Arduino IDE

1. Install the ESP32 board package (core 3.x) through the Boards Manager and select your board under Tools > Board, for example "ESP32 Dev Module".
2. Open Sketch > Include Library > Manage Libraries and search for `espFace`. Accept the dependency prompt so that ArduinoJson 7 is installed too.
3. Open File > Examples > espFace > Minimal.

::: tip
Bluetooth Classic needs a larger app partition (Tools > Partition Scheme > "Minimal SPIFFS" or "Huge APP"). See [Transports](/guide/transports).
:::

## Install with PlatformIO

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
lib_deps =
  espFace
  bblanchon/ArduinoJson@^7.0.0
; optional transports are build flags plus a library:
; build_flags = -DESPFACE_BLE
; lib_deps = ... h2zero/NimBLE-Arduino@^2.5.1
```

Build flags such as `-DESPFACE_BLE` switch on optional transports and tune limits. See [Compile-time options](/reference/options).

## Your first sketch

This is the `Minimal` example: a gauge fed from the loop and a switch that drives the built-in LED.

```cpp
#include <espFace.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

EspFace face;
float temp = 20;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  face.begin("Minimal");
  // face.setPin("1234");                   // optional PIN pairing
  face.wifi().autoConnect();                // stored credentials, else AP "espFace-<id>"

  face.ui().gauge("temp", "Temperature", 0, 100, "°C");
  face.ui().sw("led", "LED").onChange([](bool on) { digitalWrite(LED_BUILTIN, on); });
}

void loop() {
  face.loop();
  static uint32_t last = 0;
  if (millis() - last > 1000) {
    last = millis();
    temp += 0.1f;
    if (temp > 90) temp = 20;
    face.set("temp", temp);
  }
}
```

What happens here:

- `face.begin(name)` sets the display name and starts the core.
- `face.setPin(pin)` is optional. Without it the device is open to everyone on the network.
- `face.wifi().autoConnect()` joins the stored network or, if there is none, opens the captive access point `espFace-<id>`. To store credentials from the sketch use `face.wifi().connect("ssid", "pass")` once.
- `face.ui().gauge(...)` declares an output widget. `face.ui().sw(...)` declares an input; `onChange` runs when a client flips it.
- `face.loop()` must run regularly. `face.set(id, value)` pushes a new value to every connected client.

## Flashing

- **Arduino IDE**: Upload as usual.
- **PlatformIO**: `pio run -t upload`.
- **Browser**: the hosted [flash page](/flash/) writes a merged `.bin` over WebSerial. It needs a Chromium browser over https and is meant for blank boards or release images.

## Opening the UI

### Mobile app

The app finds devices on the same WiFi through mDNS (`_espface._tcp`). If the board has no stored WiFi credentials, join its access point `espFace-<id>` first; the captive portal then shows the bootstrap page. You can also add a device by IP, by QR code, over BLE or over USB. See [Mobile app](/guide/app).

### Browser

The device serves a small bootstrap page at `http://<ip>/` that loads the renderer from the device itself, so no internet is needed. You can also open the hosted renderer for a device:

```text
https://<renderer-host>/connect/?host=<host:port>
```

That page is https while the device speaks plain `ws://`, which some browsers block as mixed content. Opening the device's own `http://<ip>/` always works. See [Web renderer](/guide/web).

## Pairing

With a PIN set, the first connection shows a PIN dialog. The client proves it knows the PIN with an HMAC-SHA256 over a fresh nonce; the PIN itself never crosses the network. On success the device issues a 32-character session token, the client stores it per device id, and later connections resume without a PIN. Tokens do not expire. They are removed by changing the PIN or by "revoke all" on the system page. Details are in [Security model](/guide/security).

## Next steps

- [Concepts](/guide/concepts): pages, groups, rows, values, props, persistence.
- [Widget catalogue](/guide/widgets): all 30 widget types with props and examples.
- [System features](/guide/system): WiFi provisioning, OTA, NTP, ntfy.
- [Fake device](/guide/fake-device): try clients without hardware.
- [FAQ and troubleshooting](/guide/faq).
