#ifdef ARDUINO
#include "WifiMgr.h"
#include <ESPmDNS.h>
#include "../core/Core.h"

namespace espface {

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
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, pass);
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

void WifiMgr::setState(State s) {
  if (s == state_) return;
  state_ = s;
  if (!core_) return;
  for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) {
    Client* c = core_->client(i);
    if (c && c->used && c->authed) core_->send(i, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "wifi.status"); writeStatus(jw); jw.endObj(); });
  }
}

void WifiMgr::loop() {
  if (state_ == Ap) dns_.processNextRequest();
  if (state_ == Connecting) {
    if (WiFi.status() == WL_CONNECTED) { logf("connected, ip %s", WiFi.localIP().toString().c_str()); startMdns(); setState(Connected); }
    else if ((int32_t)(nowMs() - deadline_) >= 0) { logf("wifi timeout"); if (fallbackAp_) startAp(); else setState(Idle); }
  } else if (state_ == Connected && WiFi.status() != WL_CONNECTED) {
    deadline_ = nowMs() + 30000; fallbackAp_ = false; setState(Connecting);
  }
}

Str WifiMgr::ip() const { return state_ == Ap ? WiFi.softAPIP().toString() : (state_ == Connected ? WiFi.localIP().toString() : Str("")); }

void WifiMgr::writeStatus(JsonWriter& jw) const {
  const char* st = state_ == Connected ? "connected" : state_ == Connecting ? "connecting" : state_ == Ap ? "ap" : "failed";
  jw.kv("st", st);
  Str i = ip(); if (i.length()) jw.kv("ip", i);
  Str s = ssid(); if (s.length()) jw.kv("ssid", s);
  if (state_ == Connected) jw.kv("rssi", (int32_t)WiFi.RSSI());
}

bool WifiMgr::handleSys(uint8_t slot, const char* cmd, void*) {
  if (strcmp(cmd, "wifi.status") == 0) {
    core_->send(slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "wifi.status"); writeStatus(jw); jw.endObj(); });
    return true;
  }
  return false;  // wifi.scan / wifi.set arrive in phase 4
}

}  // namespace espface
#endif
