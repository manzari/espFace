// Minimal espFace sketch: one gauge, one switch, WiFi from stored credentials or captive AP.
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
  face.wifi().autoConnect();                // stored credentials, else AP "espFace-<id>"
  // face.wifi().connect("ssid", "pass");   // first run: store credentials from the sketch

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
