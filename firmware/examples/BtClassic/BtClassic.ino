// Bluetooth Classic SPP (classic ESP32 only, Bluedroid): the app pairs the device like a serial adapter.
// Build with -DESPFACE_BT_CLASSIC. Not combinable with -DESPFACE_BLE (NimBLE) in one build.
#include <espFace.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

EspFace face;
float temp = 20;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  face.enableWs(false);                     // no WiFi needed; Bluedroid + WiFi together want > 100 KB free heap
  face.begin("BtClassic");
  face.setPin("1234");
  face.btClassic();                         // SPP name = device name; the session follows the SPP link

  face.ui().gauge("temp", "Temperature", 0, 100, "°C");
  face.ui().sw("led", "LED").onChange([](bool on) { digitalWrite(LED_BUILTIN, on); });
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
