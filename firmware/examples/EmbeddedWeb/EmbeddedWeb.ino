// Serves the web renderer from flash so the UI works without internet (captive AP, isolated LAN).
// Build with -DESPFACE_EMBED_WEB (PlatformIO build_flags, or the build_flags file next to this sketch in CI).
// Regenerate src/web/embed.h after a renderer build: python3 tools/embed-web.py (from firmware/).
#include <espFace.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

EspFace face;
float temp = 20;

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  face.setProject("Home").setAbout("Embedded renderer demo");
  face.begin("Embedded");
  face.wifi().autoConnect();                // AP "espFace-<id>": open the captive page, the renderer loads from the device

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
