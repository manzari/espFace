// Two UIs: the main UI on WiFi (PIN protected) and an open setup UI on BLE that provisions the WiFi credentials.
// The BLE setup UI also serves the apps' system WiFi page (sys wifi.scan / wifi.set); the widgets below do the same
// for clients that only render widgets. Build with -DESPFACE_BLE and h2zero/NimBLE-Arduino@^2.5.1.
#include <espFace.h>

EspFace face;
float temp = 20;
std::vector<String> ssids;
int scanning = 0;

void setup() {
  Serial.begin(115200);
  face.begin("Provisioning");
  face.setPin("1234");                                  // main UI
  face.wifi().autoConnect();                            // stored credentials, else AP "espFace-<id>"

  Ui& ui = face.ui();
  ui.gauge("temp", "Temperature", 0, 100, "°C");
  ui.sw("heat", "Heater");

  Ui& setup = face.addUi("setup");
  setup.pin("");                                        // open: no PIN over BLE, it is in radio range only
  face.ble().use(setup);                                // BLE serves the setup UI, WiFi keeps the main UI
  setup.header("WiFi setup");
  setup.label("status", "Status");
  setup.button("scan", "Scan networks").onClick([] { WiFi.scanNetworks(true); scanning = 1; });
  setup.select("net", "Network", {"(scan first)"}).onChange([](int i) {
    if (i >= 0 && i < (int)ssids.size()) face.core().findUi("setup")->set("ssid", ssids[i].c_str());
  });
  setup.text("ssid", "SSID", 32).hint("or pick a network above");
  setup.text("pass", "Password", 64).secret();
  setup.button("connect", "Connect").onClick([] {
    Ui& s = *face.core().findUi("setup");
    String ssid = s.get("ssid") ? s.get("ssid")->asStr() : "";
    if (!ssid.length()) { s.set("status", "SSID required"); return; }
    face.wifi().connect(ssid.c_str(), s.get("pass") ? s.get("pass")->asStr().c_str() : "");   // stored; AP fallback on failure
  });
}

void loop() {
  face.loop();
  Ui& setup = *face.core().findUi("setup");
  if (scanning == 1) {
    int n = WiFi.scanComplete();
    if (n >= 0) {
      ssids.clear(); std::vector<const char*> opts;
      for (int i = 0; i < n && ssids.size() < 20; i++) if (WiFi.SSID(i).length()) ssids.push_back(WiFi.SSID(i));
      for (auto& s : ssids) opts.push_back(s.c_str());
      if (opts.empty()) opts.push_back("(none found)");
      setup.prop("net").options(opts);
      WiFi.scanDelete(); scanning = 0;
    }
  }
  static uint32_t last = 0;
  if (millis() - last > 1000) {
    last = millis();
    temp += 0.1f; if (temp > 90) temp = 20;
    face.set("temp", temp);
    const char* st = face.wifi().connected() ? "connected" : face.wifi().apMode() ? "access point" : face.wifi().state() == espface::WifiMgr::Connecting ? "connecting" : "failed";
    String line = String(st); if (face.wifi().ip().length()) { line += " "; line += face.wifi().ip(); }
    setup.set("status", line.c_str());
  }
}
