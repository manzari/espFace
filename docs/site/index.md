---
layout: home
title: espFace
hero:
  name: espFace
  text: Your ESP32 describes its UI. The apps draw it.
  tagline: An Arduino library, a native Android/iOS app and a web renderer that share one small JSON protocol. No web code, no app code, no cloud.
  actions:
    - theme: brand
      text: Getting started
      link: /guide/getting-started
    - theme: alt
      text: API reference
      link: /reference/espface
    - theme: alt
      text: Source
      link: https://git.hauptstadt.monster/manzari/espFace
features:
  - title: Builder API, 30 widgets
    details: Gauges, charts, sliders, switches, joystick, tables, logs, maps and more, declared in a few chained calls. Pages, group cards and rows give the layout.
  - title: Native app and web renderer
    details: A Flutter app for Android and iOS and a Preact renderer for the browser draw the same UI from the same description. Both are fully data driven.
  - title: Four transports
    details: WiFi WebSocket, BLE (NimBLE), USB/UART serial and Bluetooth Classic SPP share one session layer. Add a transport with one call.
  - title: Security without TLS
    details: Optional PIN with HMAC-SHA256 challenge-response, per-device session tokens, lockout after five wrong tries, capabilities such as OTA are opt-in.
  - title: System features included
    details: WiFi provisioning with captive portal, OTA push and by URL, NTP, direct ntfy notifications, device info, reboot and PIN management.
  - title: Fake device and CI
    details: A Node implementation of the device side lets you develop clients and test reconnects without hardware. Forgejo CI runs protocol, firmware, app and web tests.
---

## In 20 lines

```cpp
#include <espFace.h>
EspFace face;
void setup() {
  face.begin("Boiler");
  face.setPin("1234");
  face.wifi().autoConnect();
  face.ui().gauge("temp", "Temperature", 0, 120, "°C");
  face.ui().sw("pump", "Pump").onChange([](bool on) { digitalWrite(PUMP, on); });
}
void loop() { face.loop(); face.set("temp", readTemp()); }
```

Flash it, open the espFace app or `http://<device-ip>/` in a browser, enter the PIN once, and the gauge and the switch are there. Continue with [Getting started](/guide/getting-started) or read how the pieces fit together in [Concepts](/guide/concepts).
