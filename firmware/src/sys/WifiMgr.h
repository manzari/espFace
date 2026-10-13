#pragma once
#include "../core/Platform.h"
#ifdef ARDUINO
#include <WiFi.h>
#include <DNSServer.h>
#include "Store.h"
#include "../proto/Writer.h"

namespace espface {

class Core;

// STA/AP management, captive DNS and mDNS advertisement.
class WifiMgr {
 public:
  enum State : uint8_t { Idle, Connecting, Connected, Ap };
  void begin(Core* core, Store* store, const char* hostname, uint16_t port);
  void connect(const char* ssid, const char* pass, bool save = true, uint32_t timeoutMs = 15000);
  void autoConnect(uint32_t timeoutMs = 15000);          // stored credentials, else access point
  void startAp(const char* ssid = nullptr, const char* pass = nullptr);
  void loop();
  State state() const { return state_; }
  bool connected() const { return state_ == Connected; }
  bool apMode() const { return state_ == Ap; }
  Str ip() const;
  Str ssid() const { return state_ == Ap ? apSsid_ : WiFi.SSID(); }
  int rssi() const { return state_ == Connected ? WiFi.RSSI() : 0; }
  void writeStatus(JsonWriter& jw) const;
  bool handleSys(uint8_t slot, const char* cmd, void* doc);
  void setApPassword(const char* pass) { apPass_ = pass ? pass : ""; }

 private:
  void startMdns();
  void setState(State s);
  Core* core_ = nullptr;
  Store* store_ = nullptr;
  Str host_, apSsid_, apPass_;
  uint16_t port_ = 80;
  State state_ = Idle;
  uint32_t deadline_ = 0;
  bool fallbackAp_ = false;
  bool mdns_ = false;
  DNSServer dns_;
};

}  // namespace espface
#endif
