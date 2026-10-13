#pragma once
#include "../core/Platform.h"
#ifdef ARDUINO
#include <WiFi.h>
#include <DNSServer.h>
#include "Store.h"
#include "../proto/Writer.h"

namespace espface {

class Core;

// STA/AP management, captive DNS, mDNS advertisement, scan and provisioning (sys wifi.*).
class WifiMgr {
 public:
  enum State : uint8_t { Idle, Connecting, Connected, Failed, Ap };
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
  void sendStatus(uint8_t slot);
  void sendScan(uint8_t slot, int n);
  Core* core_ = nullptr;
  Store* store_ = nullptr;
  Str host_, apSsid_, apPass_;
  uint16_t port_ = 80;
  State state_ = Idle;
  uint32_t deadline_ = 0, apOffAt_ = 0;
  bool fallbackAp_ = false;
  bool keepAp_ = false;     // AP stays up while a provisioning attempt runs
  bool mdns_ = false;
  uint8_t scanMask_ = 0;    // slots waiting for a scan result
  DNSServer dns_;
};

}  // namespace espface
#endif
