#pragma once
#include "core/Core.h"
#ifdef ARDUINO
#include "sys/NvsStore.h"
#include "sys/WifiMgr.h"
#include "transport/WsTransport.h"

namespace espface {

// Arduino-facing facade: wires the core to NVS, WiFi and the WebSocket transport.
class EspFace {
 public:
  EspFace();
  void begin(const char* name);
  void loop();
  void beginTask(uint32_t stack = 8192, uint8_t prio = 1, int core = -1);
  void delay(uint32_t ms);

  EspFace& setPin(const char* pin, bool force = false) { core_.setPin(pin, force); return *this; }
  EspFace& setProject(const char* p) { core_.setProject(p); return *this; }
  EspFace& setIcon(const char* i) { core_.setIcon(i); return *this; }
  EspFace& setVersion(const char* v) { core_.setVersion(v); return *this; }
  EspFace& setRepo(const char* r) { core_.setRepo(r); return *this; }
  EspFace& setAbout(const char* a) { core_.setAbout(a); return *this; }
  EspFace& setPort(uint16_t port) { ws_.setPort(port); return *this; }
  EspFace& setRendererHost(const char* host) { ws_.setRendererHost(host); return *this; }
  EspFace& enableOta(bool on) { ota_ = on; return *this; }   // used from phase 4

  Ui& ui() { return core_.ui(); }
  Ui& addUi(const char* name) { return core_.addUi(name); }
  WifiMgr& wifi() { return wifi_; }
  WsTransport& ws() { return ws_; }
  Core& core() { return core_; }

  bool set(const char* id, bool v) { return core_.ui().set(id, v); }
  bool set(const char* id, float v) { return core_.ui().set(id, v); }
  bool set(const char* id, double v) { return core_.ui().set(id, (float)v); }
  bool set(const char* id, int v) { return core_.ui().set(id, v); }
  bool set(const char* id, const char* v) { return core_.ui().set(id, v); }
  bool set(const char* id, const String& v) { return core_.ui().set(id, v.c_str()); }
  void push(const char* chart, const char* series, float v) { core_.ui().push(chart, series, v, chartTs()); }
  void log(const char* msg, const char* color = nullptr) { core_.log(msg, color); }
  void log(const char* logId, const char* msg, const char* color) { core_.ui().logLine(logId, msg, color); }
  void toast(const char* lvl, const char* msg) { core_.toast(lvl, msg); }
  uint8_t clients() const { return core_.clients(); }
  uint32_t time() const { return core_.time(); }
  void setTime(uint32_t unix) { core_.setTime(unix, true); }
  void onConnect(std::function<void(const ClientInfo&)> fn) { core_.onConnect(fn); }
  void onDisconnect(std::function<void(const ClientInfo&)> fn) { core_.onDisconnect(fn); }
  void onReboot(std::function<void(RebootReason)> fn) { core_.onReboot(fn); }
  void reboot(uint32_t delayMs = 500) { core_.requestReboot(RebootReason::Sketch, delayMs); }
  const char* id() const { return core_.id(); }

 private:
  uint64_t chartTs() const { uint32_t t = core_.time(); return t ? (uint64_t)t * 1000ULL + (millis() % 1000) : (uint64_t)millis(); }
  static void taskFn(void* self);
  Core core_;
  NvsStore store_;
  WifiMgr wifi_;
  WsTransport ws_;
  bool ota_ = false;
  bool taskRunning_ = false;
  bool begun_ = false;
};

}  // namespace espface

using espface::EspFace;
using espface::Ui;
using espface::WidgetRef;
using espface::Value;
using espface::ClientInfo;
using espface::RebootReason;
using espface::Str;
#endif
