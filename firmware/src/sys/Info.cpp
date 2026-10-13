#include "Info.h"

namespace espface {

const char* resetReasonName(int r, bool otaMarker) {
  switch (r) {
    case 1: return "power";                     // ESP_RST_POWERON
    case 2: return "button";                    // ESP_RST_EXT
    case 3: return otaMarker ? "ota" : "sw";    // ESP_RST_SW
    case 4: case 15: return "panic";            // ESP_RST_PANIC, ESP_RST_CPU_LOCKUP
    case 5: case 6: case 7: return "wdt";       // INT_WDT, TASK_WDT, WDT
    case 9: case 14: return "brownout";         // ESP_RST_BROWNOUT, ESP_RST_PWR_GLITCH
    default: return "other";
  }
}

void writeInfo(JsonWriter& jw, const InfoData& d) {
  jw.kv("chip", d.chip);
  jw.kv("heap", d.heap);
  jw.kv("heapmin", d.heapmin);
  if (d.ip.length()) jw.kv("ip", d.ip);
  if (d.ssid.length()) jw.kv("ssid", d.ssid);
  if (d.hasRssi) jw.kv("rssi", d.rssi);
  if (d.mac.length()) jw.kv("mac", d.mac);
  jw.kv("rr", d.rr);
}

}  // namespace espface
