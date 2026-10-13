// BLE-only device: no WiFi, no web server. The app connects over GATT (service 0000ea00-...).
// Build with -DESPFACE_BLE and the NimBLE-Arduino library (h2zero/NimBLE-Arduino@^2.5.1).
#include <espFace.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

EspFace face;
float temp = 20;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  face.enableWs(false);                     // no http/WebSocket server, WiFi radio stays off
  face.begin("BleOnly");
  face.setPin("1234");                      // same HMAC pairing as over WiFi
  face.ble();                               // advertises as "BleOnly" with the espFace service UUID

  face.ui().gauge("temp", "Temperature", 0, 100, "°C");
  face.ui().sw("led", "LED").onChange([](bool on) { digitalWrite(LED_BUILTIN, on); });
  face.ui().slider("bright", "Brightness", 0, 255).persist();
  face.ui().log("term", "Log", 50);
  face.onConnect([](const ClientInfo& c) { face.log("term", c.transport, "#0f0"); });
}

void loop() {
  face.loop();
  static uint32_t last = 0;
  if (millis() - last > 1000) {
    last = millis();
    temp += 0.1f; if (temp > 90) temp = 20;
    face.set("temp", temp);
  }
}
