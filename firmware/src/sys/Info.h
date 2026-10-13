#pragma once
#include "../core/Platform.h"
#include "../proto/Writer.h"

namespace espface {

// Fields of the sys info reply that the platform layer provides.
struct InfoData {
  const char* chip = "";
  const char* rr = "other";
  uint32_t heap = 0, heapmin = 0;
  Str ip, ssid, mac;
  int32_t rssi = 0;
  bool hasRssi = false;
};

// Maps esp_reset_reason() values (ESP-IDF numeric codes) to the protocol strings.
const char* resetReasonName(int espRst, bool otaMarker);
void writeInfo(JsonWriter& jw, const InfoData& d);

}  // namespace espface
