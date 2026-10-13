#ifdef ARDUINO
#include "Face.h"
#include "web/bootstrap.h"
#include <esp_system.h>

namespace espface {

static const char* resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power";
    case ESP_RST_SW: return "sw";
    case ESP_RST_PANIC: return "panic";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "wdt";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_EXT: return "button";
    default: return "other";
  }
}

EspFace::EspFace() {}

void EspFace::begin(const char* name) {
  if (begun_) return;
  begun_ = true;
  store_.begin("espface");
  uint64_t mac = ESP.getEfuseMac();
  uint8_t b[3] = {(uint8_t)(mac >> 40), (uint8_t)(mac >> 32), (uint8_t)(mac >> 24)};
  char id[7]; toHex(b, 3, id);
  core_.setId(id);
  if (!core_.fw()[0]) core_.setVersion(ESPFACE_LIB_VERSION);
  ws_.setBootstrap(ESPFACE_BOOTSTRAP_HTML, sizeof(ESPFACE_BOOTSTRAP_HTML) - 1, false);
  core_.addTransport(&ws_);
  core_.begin(name, &store_);
  wifi_.begin(&core_, &store_, name, ws_.port());
  core_.infoFill = [this](JsonWriter& jw) {
    jw.kv("chip", ESP.getChipModel());
    jw.kv("heap", (uint32_t)ESP.getFreeHeap());
    jw.kv("heapmin", (uint32_t)ESP.getMinFreeHeap());
    Str ip = wifi_.ip(); if (ip.length()) jw.kv("ip", ip);
    Str ssid = wifi_.ssid(); if (ssid.length()) jw.kv("ssid", ssid);
    if (wifi_.connected()) jw.kv("rssi", (int32_t)wifi_.rssi());
    String m = WiFi.macAddress(); m.toLowerCase(); jw.kv("mac", m);
    jw.kv("rr", resetReason());
  };
  core_.sysHook = [this](uint8_t slot, const char* cmd, void* doc) { return wifi_.handleSys(slot, cmd, doc); };
  core_.rebootFn = [] { ESP.restart(); };
  logf("espFace %s \"%s\" id %s", ESPFACE_LIB_VERSION, name, core_.id());
}

void EspFace::loop() {
  if (taskRunning_) return;
  wifi_.loop();
  core_.loop();
}

void EspFace::taskFn(void* self) {
  EspFace* f = (EspFace*)self;
  for (;;) { f->wifi_.loop(); f->core_.loop(); vTaskDelay(pdMS_TO_TICKS(5)); }
}

void EspFace::beginTask(uint32_t stack, uint8_t prio, int core) {
  if (taskRunning_) return;
  taskRunning_ = true;
  if (core < 0) xTaskCreate(taskFn, "espface", stack, this, prio, nullptr);
  else xTaskCreatePinnedToCore(taskFn, "espface", stack, this, prio, nullptr, core);
}

void EspFace::delay(uint32_t ms) {
  uint32_t end = millis() + ms;
  while ((int32_t)(end - millis()) > 0) { loop(); ::delay(1); }
}

}  // namespace espface
#endif
