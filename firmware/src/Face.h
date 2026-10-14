#pragma once
#include "core/Core.h"
#include "sys/Ntfy.h"
#ifdef ARDUINO
#include "sys/NvsStore.h"
#include "sys/WifiMgr.h"
#include "sys/Ota.h"
#include "sys/OtaEsp.h"
#include "sys/NtfyEsp.h"
#include "transport/WsTransport.h"
#include "transport/StreamTransport.h"
#ifdef ESPFACE_BLE
#include "transport/BleTransport.h"
#endif
#ifdef ESPFACE_BT_CLASSIC
#include "transport/BtSerial.h"
#endif

namespace espface {

// Arduino-facing facade: wires the core to NVS, WiFi, OTA, NTP, ntfy and the WebSocket, stream, BLE and SPP transports.
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
  EspFace& enableWs(bool on) { wsOn_ = on; return *this; }              // before begin(); false skips the http/WebSocket server
  EspFace& logTo(Print* p) { setLogOutput(p); return *this; }           // library log lines; nullptr silences them
  EspFace& setRendererHost(const char* host) { ws_.setRendererHost(host); return *this; }
  // Inline on purpose: Update, HTTPClient and TLS are linked only when a sketch calls these.
  EspFace& enableOta(bool on) {                                // caps ota + otaurl, POST /update
    otaOn_ = on;
    if (on) {
      if (!otaBackend_) { static UpdateBackend be; otaBackend_ = &be; ota_.begin(&core_, &be, &store_); otaInstallUrlFetch(ota_); }
      core_.addCap("ota"); core_.addCap("otaurl");
      otaHttp_ = [this] { if (!httpUpdate_ && ws_.running()) { otaRegisterHttp(ota_, core_, ws_.handle()); httpUpdate_ = true; } };
      if (begun_) otaHttp_();
    } else { core_.removeCap("ota"); core_.removeCap("otaurl"); ota_.abort(); }
    return *this;
  }
  EspFace& setOtaCaCert(const char* pem) { ca_ = pem; ota_.setCaCert(pem); return *this; }   // https verification for ota.url and ntfy (default: unverified)
  EspFace& enableNtp(bool on, const char* server = "pool.ntp.org", const char* tz = nullptr);   // tz: POSIX string, e.g. "CET-1CEST,M3.5.0,M10.5.0/3"
  EspFace& ntfy(const char* server, const char* topic, const char* token = nullptr) {
    ntfy_.configure(server, topic, token);
    if (ntfy_.configured()) { core_.addCap("ntfy"); if (!ntfy_.sender) ntfyInstallSender(ntfy_, &ca_); } else core_.removeCap("ntfy");
    return *this;
  }
  EspFace& ntfyRateLimit(uint32_t ms) { ntfy_.setRateLimit(ms); return *this; }
  bool notify(const char* title, const char* msg, Ntfy prio = Ntfy::Default) { return ntfy_.notify(title, msg, prio, millis()); }

  Ui& ui() { return core_.ui(); }
  Ui& addUi(const char* name) { return core_.addUi(name); }
  WifiMgr& wifi() { return wifi_; }
  WsTransport& ws() { return ws_; }
  // Any Stream (UART, USB CDC, BluetoothSerial) as a one-client line transport; may be called before or after begin().
  StreamTransport& serial(Stream& s, const char* name = "serial") { auto* t = new StreamTransport(s, name); core_.addTransport(t); return *t; }
#ifdef ESPFACE_BLE
  BleTransport& ble() { if (!bleAdded_) { bleAdded_ = true; core_.addTransport(&ble_); } return ble_; }   // enables BLE
#endif
#ifdef ESPFACE_BT_CLASSIC
  BtSerialTransport& btClassic(const char* name = nullptr) {                                           // enables Bluetooth Classic SPP
    if (!bt_) { bt_ = new BtSerialTransport(); if (name) bt_->setName(name); core_.addTransport(bt_); }
    return *bt_;
  }
#endif
  Core& core() { return core_; }
  Ota& ota() { return ota_; }
  Notifier& notifier() { return ntfy_; }

  bool set(const char* id, bool v) { return core_.ui().set(id, v); }
  bool set(const char* id, float v) { return core_.ui().set(id, v); }
  bool set(const char* id, double v) { return core_.ui().set(id, (float)v); }
  bool set(const char* id, int v) { return core_.ui().set(id, v); }
  bool set(const char* id, const char* v) { return core_.ui().set(id, v); }
  bool set(const char* id, const String& v) { return core_.ui().set(id, v.c_str()); }
  bool set(const char* id, uint32_t v) { return core_.ui().set(id, v); }
  bool set(const char* id, int x, int y) { return core_.ui().set(id, x, y); }
  bool setRows(const char* id, const char* rowsJson) { return core_.ui().setRows(id, rowsJson); }
  bool setPoints(const char* id, const char* pointsJson) { return core_.ui().setPoints(id, pointsJson); }
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
  // Writes pending persisted values now, e.g. before deep sleep or your own ESP.restart().
  void flushPersist() { core_.flushPersist(); }
  const char* id() const { return core_.id(); }
  const char* resetReason() const { return rr_; }

 private:
  uint64_t chartTs() const { uint32_t t = core_.time(); return t ? (uint64_t)t * 1000ULL + (millis() % 1000) : (uint64_t)millis(); }
  static void taskFn(void* self);
  void tick();
  void ntpLoop();
  Core core_;
  NvsStore store_;
  WifiMgr wifi_;
  WsTransport ws_;
#ifdef ESPFACE_BLE
  BleTransport ble_;
  bool bleAdded_ = false;
#endif
#ifdef ESPFACE_BT_CLASSIC
  BtSerialTransport* bt_ = nullptr;
#endif
  bool wsOn_ = true;
  Ota ota_;
  OtaBackend* otaBackend_ = nullptr;
  std::function<void()> otaHttp_;
  Notifier ntfy_;
  const char* ca_ = nullptr;
  const char* rr_ = "other";
  bool otaOn_ = false, httpUpdate_ = false;
  bool ntp_ = false, ntpSynced_ = false;
  uint32_t ntpAt_ = 0;
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
using espface::Ntfy;
using espface::Str;
#endif
