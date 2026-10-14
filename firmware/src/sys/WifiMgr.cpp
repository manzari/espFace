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
  timeoutMs_ = timeoutMs; deadline_ = nowMs() + timeoutMs;
  fallbackAp_ = true; attempt_ = true; retrying_ = false; lost_ = false; fails_ = 0;
  setState(Connecting);
  logf("connecting to %s", ssid);
}

// One more STA attempt with the stored credentials (after a lost link or out of the AP fallback).
void WifiMgr::retryBegin(uint32_t now) {
  Str ssid, pass;
  retrying_ = false;
  if (!store_ || !store_->getStr("ssid", ssid) || !ssid.length()) return;
  store_->getStr("pass", pass);
  bool ap = state_ == Ap || keepAp_;
  WiFi.mode(ap ? WIFI_AP_STA : WIFI_STA);
  WiFi.disconnect(false, false);
  WiFi.begin(ssid.c_str(), pass.length() ? pass.c_str() : nullptr);
  attempt_ = true; deadline_ = now + timeoutMs_; reconnects_++;
  logf("wifi retry %u", (unsigned)fails_);
  if (state_ != Ap) setState(Connecting);
}

void WifiMgr::scheduleRetry(uint32_t now) {
  retrying_ = false;
  if (!maxS_) return;
  uint32_t s = minS_ ? minS_ : 1;
  if (state_ == Ap || keepAp_) s = maxS_;
  else for (uint8_t i = 1; i < fails_ && s < maxS_; i++) s *= 2;
  if (s > maxS_) s = maxS_;
  retryAt_ = now + s * 1000u; retrying_ = true;
  logf("wifi down, next try in %lu s", (unsigned long)s);
}

void WifiMgr::onConnected(uint32_t now) {
  logf("connected, ip %s", WiFi.localIP().toString().c_str());
  fails_ = 0; lost_ = false; attempt_ = false; retrying_ = false;
  bool ap = state_ == Ap || keepAp_;
  startMdns(); setState(Connected);          // mDNS is re-announced on every (re)connect
  if (ap) { keepAp_ = true; apOffAt_ = now + 5000; }   // the AP goes down once the status went out
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
  uint32_t now = nowMs();
  bool sta = WiFi.status() == WL_CONNECTED;
  if (state_ == Connected) {
    if (!sta) {   // link dropped: the stack's auto-reconnect is the first attempt, then our retries with backoff
      lost_ = true; fails_ = 0; fallbackAp_ = false; attempt_ = true; retrying_ = false; deadline_ = now + timeoutMs_;
      setState(Connecting);
    } else if (keepAp_ && (int32_t)(now - apOffAt_) >= 0) { keepAp_ = false; dns_.stop(); WiFi.softAPdisconnect(true); WiFi.mode(WIFI_STA); }
  } else if (sta && (attempt_ || retrying_ || state_ == Failed || state_ == Idle)) {
    onConnected(now);
  } else if (attempt_) {
    if ((int32_t)(now - deadline_) >= 0) {
      attempt_ = false;
      if (fails_ < 255) fails_++;
      if (fallbackAp_ && !lost_) { logf("wifi timeout"); setState(Failed); fallbackAp_ = false; startAp(); }
      else if (lost_ && apAfter_ && fails_ >= apAfter_ && state_ != Ap) { logf("wifi lost for %u tries, access point up", (unsigned)fails_); startAp(); }
      else if (state_ != Ap) { keepAp_ = false; WiFi.mode(WIFI_STA); setState(Failed); }
      scheduleRetry(now);
    }
  } else if (retrying_ && (int32_t)(now - retryAt_) >= 0) {
    retryBegin(now);
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
