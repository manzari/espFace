#ifdef ARDUINO
#include "Face.h"
#include "web/bootstrap.h"
#include "sys/Info.h"
#include <esp_system.h>
#include <time.h>

namespace espface {

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
  Str marker; bool otaMarker = store_.getStr("rr", marker) && marker == "ota";
  if (otaMarker) store_.remove("rr");
  rr_ = resetReasonName((int)esp_reset_reason(), otaMarker);
  ws_.setBootstrap(ESPFACE_BOOTSTRAP_HTML, sizeof(ESPFACE_BOOTSTRAP_HTML) - 1, false);
  if (wsOn_) core_.addTransport(&ws_);
  core_.begin(name, &store_);
  wifi_.begin(&core_, &store_, name, ws_.port());
  core_.infoFill = [this](JsonWriter& jw) {
    InfoData d;
    d.chip = ESP.getChipModel(); d.rr = rr_;
    d.heap = ESP.getFreeHeap(); d.heapmin = ESP.getMinFreeHeap();
    d.ip = wifi_.ip(); d.ssid = wifi_.ssid();
    if (wifi_.connected()) { d.rssi = wifi_.rssi(); d.hasRssi = true; }
    d.mac = WiFi.macAddress(); d.mac.toLowerCase();
    writeInfo(jw, d);
  };
  core_.sysHook = [this](uint8_t slot, const char* cmd, void* doc) { return wifi_.handleSys(slot, cmd, doc) || ota_.handleSys(slot, cmd, doc); };
  core_.binaryHook = [this](uint8_t slot, const uint8_t* data, size_t len) { return ota_.onBinary(slot, data, len); };
  core_.closeHook = [this](uint8_t slot) { ota_.onClose(slot); };
  core_.rebootFn = [] { ESP.restart(); };
  if (otaHttp_) otaHttp_();
  logf("espFace %s \"%s\" id %s rr %s", ESPFACE_LIB_VERSION, name, core_.id(), rr_);
}

EspFace& EspFace::enableNtp(bool on, const char* server, const char* tz) {
  ntp_ = on; ntpSynced_ = false; ntpAt_ = 0;
  if (on) { if (tz) configTzTime(tz, server); else configTime(0, 0, server); core_.addCap("ntp"); }
  else core_.removeCap("ntp");
  return *this;
}

void EspFace::ntpLoop() {
  uint32_t now = millis();
  if (ntpAt_ && (uint32_t)(now - ntpAt_) < (ntpSynced_ ? 600000u : 1000u)) return;
  ntpAt_ = now ? now : 1;
  time_t t = ::time(nullptr);
  if (t > 1600000000) { core_.setTime((uint32_t)t, true); if (!ntpSynced_) logf("ntp time %lu", (unsigned long)t); ntpSynced_ = true; }
}

void EspFace::tick() {
  wifi_.loop();
  ota_.loop();
  ntfy_.loop(millis());
  if (ntp_) ntpLoop();
  core_.loop();
}

void EspFace::loop() {
  if (taskRunning_) return;
  tick();
}

void EspFace::taskFn(void* self) {
  EspFace* f = (EspFace*)self;
  for (;;) { f->tick(); vTaskDelay(pdMS_TO_TICKS(5)); }
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
