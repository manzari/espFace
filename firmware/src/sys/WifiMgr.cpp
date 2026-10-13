#ifdef ARDUINO
#include "WifiMgr.h"
#include <ESPmDNS.h>
#include <ArduinoJson.h>
#include "../core/Core.h"

namespace espface {

#define DOC (*(JsonDocument*)doc)

void WifiMgr::begin(Core* core, Store* store, const char* hostname, uint16_t port) {
  core_ = core; store_ = store; host_ = hostname; port_ = port;
  WiFi.persistent(false);
  WiFi.setHostname(hostname);
  WiFi.setAutoReconnect(true);
  apSsid_ = "espFace-"; apSsid_ += core->id();
  core->addCap("wifi");
}

void WifiMgr::connect(const char* ssid, const char* pass, bool save, uint32_t timeoutMs) {
  if (save && store_) { store_->putStr("ssid", Str(ssid)); store_->putStr("pass", Str(pass ? pass : "")); }
  keepAp_ = state_ == Ap || keepAp_;
  WiFi.mode(keepAp_ ? WIFI_AP_STA : WIFI_STA);
  WiFi.begin(ssid, pass && pass[0] ? pass : nullptr);
  deadline_ = nowMs() + timeoutMs;
  fallbackAp_ = true;
  setState(Connecting);
  logf("connecting to %s", ssid);
}

void WifiMgr::autoConnect(uint32_t timeoutMs) {
  Str ssid, pass;
  if (store_ && store_->getStr("ssid", ssid) && ssid.length()) { store_->getStr("pass", pass); connect(ssid.c_str(), pass.c_str(), false, timeoutMs); return; }
  startAp();
}

void WifiMgr::startAp(const char* ssid, const char* pass) {
  if (ssid) apSsid_ = ssid;
  if (pass) apPass_ = pass;
  keepAp_ = false;
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apSsid_.c_str(), apPass_.length() >= 8 ? apPass_.c_str() : nullptr);
  dns_.setErrorReplyCode(DNSReplyCode::NoError);
  dns_.start(53, "*", WiFi.softAPIP());
  setState(Ap);
  logf("access point %s at %s", apSsid_.c_str(), WiFi.softAPIP().toString().c_str());
}

void WifiMgr::startMdns() {
  if (mdns_) MDNS.end();
  if (!MDNS.begin(host_.c_str())) { logf("mDNS failed"); return; }
  mdns_ = true;
  MDNS.addService("espface", "tcp", port_);
  MDNS.addServiceTxt("espface", "tcp", "id", core_->id());
  MDNS.addServiceTxt("espface", "tcp", "name", core_->name());
  MDNS.addServiceTxt("espface", "tcp", "v", "1");
  if (core_->proj()[0]) MDNS.addServiceTxt("espface", "tcp", "proj", core_->proj());
  if (core_->icon()[0]) MDNS.addServiceTxt("espface", "tcp", "icon", core_->icon());
}

void WifiMgr::sendStatus(uint8_t slot) {
  core_->send(slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "wifi.status"); writeStatus(jw); jw.endObj(); });
}

void WifiMgr::setState(State s) {
  if (s == state_) return;
  state_ = s;
  if (!core_) return;
  for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) {
    Client* c = core_->client(i);
    if (c && c->used && c->authed) sendStatus(i);
  }
}

void WifiMgr::loop() {
  if (state_ == Ap || keepAp_) dns_.processNextRequest();
  if (state_ == Connecting) {
    if (WiFi.status() == WL_CONNECTED) {
      logf("connected, ip %s", WiFi.localIP().toString().c_str());
      startMdns(); setState(Connected);
      if (keepAp_) apOffAt_ = nowMs() + 5000;   // let the provisioning client read the status first
    } else if ((int32_t)(nowMs() - deadline_) >= 0) {
      logf("wifi timeout");
      setState(Failed);
      if (fallbackAp_) startAp(); else { keepAp_ = false; WiFi.mode(WIFI_STA); }
    }
  } else if (state_ == Connected) {
    if (WiFi.status() != WL_CONNECTED) { deadline_ = nowMs() + 30000; fallbackAp_ = false; setState(Connecting); }
    else if (keepAp_ && (int32_t)(nowMs() - apOffAt_) >= 0) { keepAp_ = false; dns_.stop(); WiFi.softAPdisconnect(true); WiFi.mode(WIFI_STA); }
  }
  if (scanMask_) {
    int n = WiFi.scanComplete();
    if (n == WIFI_SCAN_RUNNING) return;
    for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) if (scanMask_ & (1 << i)) sendScan(i, n < 0 ? 0 : n);
    scanMask_ = 0;
    WiFi.scanDelete();
  }
}

Str WifiMgr::ip() const {
  if (state_ == Connected) return WiFi.localIP().toString();
  if (state_ == Ap || keepAp_) return WiFi.softAPIP().toString();
  return Str("");
}

void WifiMgr::writeStatus(JsonWriter& jw) const {
  const char* st = state_ == Connected ? "connected" : state_ == Connecting ? "connecting" : state_ == Ap ? "ap" : "failed";
  jw.kv("st", st);
  Str i = ip(); if (i.length()) jw.kv("ip", i);
  Str s = ssid(); if (s.length()) jw.kv("ssid", s);
  if (state_ == Connected) jw.kv("rssi", (int32_t)WiFi.RSSI());
}

void WifiMgr::sendScan(uint8_t slot, int n) {
  Client* c = core_->client(slot);
  if (!c || !c->used || !c->authed) return;
  core_->send(slot, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "wifi.scan"); jw.key("ap"); jw.beginArr();
    int out = 0;
    for (int i = 0; i < n && out < 30; i++) {
      String s = WiFi.SSID(i);
      if (!s.length() || s.length() > 32) continue;
      bool dup = false;
      for (int j = 0; j < i; j++) if (WiFi.SSID(j) == s) { dup = true; break; }   // results are sorted by RSSI
      if (dup) continue;
      jw.beginObj(); jw.kv("ssid", s); jw.kv("rssi", (int32_t)WiFi.RSSI(i)); jw.kv("enc", WiFi.encryptionType(i) != WIFI_AUTH_OPEN); jw.endObj();
      out++;
    }
    jw.endArr(); jw.endObj();
  });
}

bool WifiMgr::handleSys(uint8_t slot, const char* cmd, void* doc) {
  if (strcmp(cmd, "wifi.status") == 0) { sendStatus(slot); return true; }
  if (strcmp(cmd, "wifi.scan") == 0) {
    if (!scanMask_) {
      if (WiFi.getMode() == WIFI_AP) { WiFi.mode(WIFI_AP_STA); keepAp_ = true; }
      WiFi.scanNetworks(true, false);
    }
    scanMask_ |= (uint8_t)(1 << slot);
    return true;
  }
  if (strcmp(cmd, "wifi.set") == 0) {
    const char* ssid = DOC["ssid"];
    if (!ssid || !ssid[0] || strlen(ssid) > 32) { core_->sendErr(slot, 7, "ssid required", cmd); return true; }
    const char* pass = DOC["pass"] | "";
    if (scanMask_) { WiFi.scanDelete(); scanMask_ = 0; }
    connect(ssid, pass, true, 15000);
    return true;
  }
  return false;
}

}  // namespace espface
#endif
