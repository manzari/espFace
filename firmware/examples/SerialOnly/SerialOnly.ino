// UI over the USB serial port (USB CDC or UART bridge), no WiFi, no web server.
// The app talks to it through USB OTG; on a PC any serial terminal shows the JSON lines (one message per line).
#include <espFace.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

EspFace face;
float temp = 20;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  face.logTo(nullptr);                      // the UI shares Serial: keep library log lines off the wire
  face.enableWs(false);
  face.begin("SerialOnly");
  face.serial(Serial);                      // one client per stream; a new hello line restarts the session
  // face.serial(Serial1).setIdleTimeout(60000);   // a second UI on a UART, closed after 60 s of silence

  face.ui().gauge("temp", "Temperature", 0, 100, "°C");
  face.ui().sw("led", "LED").onChange([](bool on) { digitalWrite(LED_BUILTIN, on); });
  face.ui().text("note", "Note", 32).persist();
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
