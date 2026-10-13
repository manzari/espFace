// Direct ntfy notifications from the device: a button sends a test message, a threshold sends an alert.
// The device POSTs to https://<server>/<topic> itself, rate-limited (default one message per 10 s).
#include <espFace.h>

EspFace face;
float temp = 20;
bool alerted = false;

void setup() {
  Serial.begin(115200);
  face.setVersion("1.0.0").setAbout("ntfy demo");
  face.begin("Notify");
  face.wifi().autoConnect();
  face.ntfy("https://ntfy.sh", "espface-demo");      // third argument: access token for protected topics
  face.ntfyRateLimit(10000);
  face.enableNtp(true);                               // alerts carry a real timestamp in the device log

  face.ui().gauge("temp", "Temperature", 0, 100, "°C");
  face.ui().slider("limit", "Alert above", 20, 100, 1, "°C").persist();
  face.ui().button("test", "Send test notification").onClick([] {
    bool queued = face.notify("espFace", "Hello from the device", Ntfy::Default);
    face.toast(queued ? "info" : "warn", queued ? "Notification queued" : "Queue full or ntfy not configured");
  });
  face.ui().label("sent", "Sent");
}

void loop() {
  face.loop();
  static uint32_t last = 0;
  if (millis() - last > 1000) {
    last = millis();
    temp += 0.5f; if (temp > 95) temp = 20;
    face.set("temp", temp);
    face.set("sent", (int)face.notifier().sent());
    float limit = face.ui().get("limit") ? face.ui().get("limit")->asFloat() : 80;
    if (temp > limit && !alerted) { alerted = true; char m[48]; snprintf(m, sizeof m, "Temperature %.1f °C", (double)temp); face.notify("Overheat", m, Ntfy::High); }
    if (temp < limit - 5) alerted = false;
  }
}
