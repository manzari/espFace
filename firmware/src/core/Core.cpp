#include "Core.h"
#include <ArduinoJson.h>

namespace espface {

#define DOC (*(JsonDocument*)doc)

static Value toValue(JsonVariantConst v) {
  if (v.is<bool>()) return Value::ofBool(v.as<bool>());
  if (v.is<const char*>()) return Value::ofStr(v.as<const char*>());
  if (v.is<JsonArrayConst>()) {
    JsonArrayConst a = v.as<JsonArrayConst>();
    if (a.size() == 2 && a[0].is<float>() && a[1].is<float>() && !a[0].is<bool>()) return Value::ofPair((int16_t)a[0].as<float>(), (int16_t)a[1].as<float>());
    Str raw; serializeJson(v, raw); return Value::ofRaw(raw);
  }
  if (v.is<float>()) {
    float f = v.as<float>();
    if (v.is<long>() && f == (float)v.as<long>()) return Value::ofInt((int32_t)v.as<long>());
    return Value::ofFloat(f);
  }
  return Value();
}

Core::Core() { uis_.push_back(new Ui("main")); for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) clients_[i].slot = i; }
Core::~Core() { for (auto u : uis_) delete u; }

void Core::begin(const char* name, Store* store) {
  name_ = name; store_ = store; fw_ = fw_.length() ? fw_ : "0.0.0";
  if (!id_.length()) { uint8_t r[3]; randomBytes(r, 3); char h[7]; toHex(r, 3, h); id_ = h; }
  auth_.begin(store);
  for (auto u : uis_) u->attach(this, store);
  addCap("pin"); addCap("reboot"); addCap("info"); addCap("chart");
  for (auto t : trs_) t->begin();
}

Ui& Core::addUi(const char* name) { Ui* u = new Ui(name); u->attach(this, store_); uis_.push_back(u); return *u; }
Ui* Core::findUi(const char* name) { for (auto u : uis_) if (strcmp(u->name(), name) == 0) return u; return nullptr; }
void Core::addTransport(Transport* t) { t->attach(this); trs_.push_back(t); }
void Core::addCap(const char* cap) { if (!hasCap(cap)) caps_.push_back(Str(cap)); }
void Core::removeCap(const char* cap) { for (size_t i = 0; i < caps_.size(); i++) if (strEq(caps_[i], cap)) { caps_.erase(caps_.begin() + i); return; } }
bool Core::hasCap(const char* cap) const { for (auto& c : caps_) if (strEq(c, cap)) return true; return false; }
uint8_t Core::clients() const { uint8_t n = 0; for (auto& c : clients_) if (c.used && c.authed) n++; return n; }

// ---- sending ------------------------------------------------------------------
void Core::send(uint8_t slot, const std::function<void(JsonWriter&)>& fill) {
  Client* c = client(slot);
  if (!c || !c->used || !c->tr) return;
  FrameSink sink(*c->tr, slot);
  { JsonWriter jw(sink); fill(jw); }
  sink.end();
}

void Core::sendErr(uint8_t slot, int code, const char* msg, const char* ref) {
  send(slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "err"); jw.kv("code", (int32_t)code); jw.kv("msg", msg); if (ref) jw.kv("ref", ref); jw.endObj(); });
}

void Core::uiBroadcast(Ui& ui, const std::function<void(JsonWriter&)>& fill) {
  for (auto& c : clients_) if (c.used && c.authed && &uiFor(c) == &ui) send(c.slot, fill);
}

void Core::uiValueChanged(Ui&, uint16_t) {}

void Core::uiRebuilt(Ui& ui) {
  for (auto& c : clients_) if (c.used && c.authed && &uiFor(c) == &ui) { send(c.slot, [&](JsonWriter& jw) { ui.writeUi(jw); }); sendFullUpd(c); }
}

void Core::toast(const char* lvl, const char* msg) {
  for (auto& c : clients_) if (c.used && c.authed) send(c.slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "toast"); jw.kv("lvl", lvl); jw.kv("msg", msg); jw.endObj(); });
}

// ---- connections ----------------------------------------------------------------
int Core::onOpen(Transport* t) {
  for (auto& c : clients_) if (!c.used) {
    uint8_t slot = c.slot; c.reset(); c.slot = slot; c.used = true; c.tr = t; c.ui = t->ui(); c.connectedAt = nowMs();
    c.page = (int8_t)uiFor(c).firstPageIdx();
    return slot;
  }
  return -1;
}

void Core::onClose(uint8_t slot) {
  Client* c = client(slot);
  if (!c || !c->used) return;
  bool wasAuthed = c->authed;
  if (closeHook) closeHook(slot);
  ClientInfo info{slot, c->tr ? c->tr->name() : "", c->isWeb};
  c->reset(); c->slot = slot;
  if (wasAuthed && onDisconnect_) onDisconnect_(info);
}

void Core::onBinary(uint8_t slot, const uint8_t* data, size_t len) {
  Client* c = client(slot);
  if (!c || !c->used || !c->authed) return;
  if (!binaryHook || !binaryHook(slot, data, len)) sendErr(slot, 10, "no binary session", "ota");
}

void Core::onMessage(uint8_t slot, const char* data, size_t len) {
  Client* c = client(slot);
  if (!c || !c->used) return;
  if (len > 2048) return sendErr(slot, 2, "message too large");
  JsonDocument d;
  if (deserializeJson(d, data, len) || !d.is<JsonObject>()) return sendErr(slot, 1, "bad json");
  const char* t = d["t"];
  if (!t) return sendErr(slot, 1, "missing t");
  void* doc = &d;
  if (!strcmp(t, "hello")) return handleHello(*c, doc);
  if (!strcmp(t, "auth")) return handleAuth(*c, doc);
  if (!c->authed) return sendErr(slot, 3, "unauthorized", t);
  if (!strcmp(t, "time")) return handleTime(*c, doc);
  if (!strcmp(t, "set")) return handleSet(*c, doc);
  if (!strcmp(t, "ev")) return handleEv(*c, doc);
  if (!strcmp(t, "dlg")) return handleDlg(*c, doc);
  if (!strcmp(t, "page")) return handlePage(*c, doc);
  if (!strcmp(t, "sys")) return handleSys(*c, doc);
  // unknown types are ignored
}

// ---- handshake ----------------------------------------------------------------
void Core::sendHello(Client& c, bool ok, const char* nonce, uint32_t lock) {
  Ui& u = uiFor(c);
  bool pin = u.hasPinOverride() ? u.pinOverride()[0] != 0 : auth_.hasPin();
  send(c.slot, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "hello"); jw.kv("v", (int32_t)ESPFACE_PROTO_VERSION); jw.kv("name", name_); jw.kv("id", id_);
    if (proj_.length()) jw.kv("proj", proj_);
    if (icon_.length()) jw.kv("icon", icon_);
    jw.kv("fw", fw_); jw.kv("auth", pin ? "pin" : "none"); jw.kv("ok", ok);
    if (!ok && lock) jw.kv("lock", (uint32_t)lock);
    else if (!ok && nonce) jw.kv("nonce", nonce);
    jw.kv("up", (uint32_t)nowMs());
    jw.key("caps"); jw.beginArr(); for (auto& cap : caps_) jw.str(cap); jw.endArr();
    jw.endObj();
  });
}

void Core::handleHello(Client& c, void* doc) {
  if (clients() >= ESPFACE_MAX_CLIENTS && !c.authed) {
    uint8_t authed = 0; for (auto& o : clients_) if (o.used && o.authed && o.slot != c.slot) authed++;
    if (authed >= ESPFACE_MAX_CLIENTS) { sendErr(c.slot, 9, "too many clients", "hello"); if (c.tr) c.tr->close(c.slot); return; }
  }
  c.helloSeen = true;
  const char* kind = DOC["client"] | "app";
  c.isWeb = strcmp(kind, "web") == 0;
  Ui& u = uiFor(c);
  bool needPin = u.hasPinOverride() ? u.pinOverride()[0] != 0 : auth_.hasPin();
  const char* tok = DOC["tok"];
  if (!needPin || (tok && auth_.validToken(tok))) { sendHello(c, true, nullptr, 0); afterAuth(c); return; }
  uint32_t lock = auth_.lockLeft(nowMs());
  if (lock) { c.hasNonce = false; sendHello(c, false, nullptr, lock); return; }
  auth_.makeNonce(c.nonce); c.hasNonce = true;
  sendHello(c, false, c.nonce, 0);
}

void Core::handleAuth(Client& c, void* doc) {
  if (!c.helloSeen) return sendErr(c.slot, 3, "hello first", "auth");
  if (c.authed) return;
  Ui& u = uiFor(c);
  const char* pinOverride = u.hasPinOverride() ? u.pinOverride() : nullptr;
  if (pinOverride && !pinOverride[0]) return;  // open UI, cannot happen after hello ok
  const char* mac = DOC["mac"];
  uint8_t left = 0; uint32_t lock = 0;
  bool ok = c.hasNonce && auth_.check(mac, c.nonce, id_.c_str(), pinOverride, nowMs(), left, lock);
  c.hasNonce = false;
  if (ok) {
    Str tok = auth_.issueToken();
    send(c.slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "auth"); jw.kv("ok", true); jw.kv("tok", tok); jw.endObj(); });
    afterAuth(c);
    return;
  }
  if (!lock) { auth_.makeNonce(c.nonce); c.hasNonce = true; }
  send(c.slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "auth"); jw.kv("ok", false); if (lock) jw.kv("lock", (uint32_t)lock); else jw.kv("left", (int32_t)left); jw.endObj(); });
}

void Core::afterAuth(Client& c) {
  c.authed = true;
  Ui& u = uiFor(c);
  send(c.slot, [&](JsonWriter& jw) { u.writeUi(jw); });
  sendFullUpd(c);
  for (uint16_t i = 0; i < u.count(); i++) if (u.at(i).ty == WType::Log) u.logHistory(i, [&](const Str& line) { FrameSink s(*c.tr, c.slot); s.write(line.c_str(), line.length()); s.end(); });
  if (onConnect_) onConnect_(ClientInfo{c.slot, c.tr ? c.tr->name() : "", c.isWeb});
}

void Core::sendFullUpd(Client& c) {
  Ui& u = uiFor(c);
  send(c.slot, [&](JsonWriter& jw) { u.writeUpd(jw, (uint8_t)(1 << c.slot), c.page, true); });
  c.lastFlush = nowMs();
}

void Core::flush(Client& c) {
  Ui& u = uiFor(c);
  if (!u.anyDirty((uint8_t)(1 << c.slot), c.page)) return;
  send(c.slot, [&](JsonWriter& jw) { u.writeUpd(jw, (uint8_t)(1 << c.slot), c.page, false); });
  c.lastFlush = nowMs();
}

// ---- messages -------------------------------------------------------------------
void Core::handleTime(Client& c, void* doc) {
  if (!DOC["unix"].is<long>()) return sendErr(c.slot, 7, "bad time", "time");
  setTime((uint32_t)DOC["unix"].as<long>(), false);
  if (DOC["tz"].is<int>()) tz_ = (int16_t)DOC["tz"].as<int>();
}

void Core::handleSet(Client& c, void* doc) {
  Ui& u = uiFor(c);
  int idx = u.find(DOC["id"] | (const char*)nullptr);
  if (idx < 0) return sendErr(c.slot, 6, "unknown widget", "set");
  int err = 0;
  if (!u.applySet((uint16_t)idx, toValue(DOC["v"]), (uint8_t)(1 << c.slot), err)) sendErr(c.slot, err, "bad value", "set");
}

void Core::handleEv(Client& c, void* doc) {
  Ui& u = uiFor(c);
  int idx = u.find(DOC["id"] | (const char*)nullptr);
  if (idx < 0) return sendErr(c.slot, 6, "unknown widget", "ev");
  int v = 1;
  JsonVariantConst jv = DOC["v"];
  if (jv.is<int>()) v = jv.as<int>();
  else if (jv.is<const char*>()) { const char* s = jv.as<const char*>(); v = s[0] ? s[0] : 0; }
  if (!u.applyEvent((uint16_t)idx, v)) sendErr(c.slot, 7, "not an event widget", "ev");
}

void Core::handleDlg(Client& c, void* doc) {
  Ui& u = uiFor(c);
  const char* id = DOC["id"];
  if (!id || !u.answerDialog(id, DOC["ok"] | false, DOC["v"] | "")) sendErr(c.slot, 6, "unknown dialog", "dlg");
}

void Core::handlePage(Client& c, void* doc) {
  Ui& u = uiFor(c);
  int p = u.pageIndexOf(DOC["id"] | (const char*)nullptr);
  if (p < 0) return sendErr(c.slot, 6, "unknown page", "page");
  c.page = (int8_t)p;
  sendFullUpd(c);
}

void Core::handleSys(Client& c, void* doc) {
  const char* cmd = DOC["cmd"];
  if (!cmd) return sendErr(c.slot, 7, "missing cmd", "sys");
  auto reply = [&](const std::function<void(JsonWriter&)>& extra) {
    send(c.slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", cmd); extra(jw); jw.endObj(); });
  };
  if (!strcmp(cmd, "info")) {
    return reply([&](JsonWriter& jw) {
      jw.kv("fw", fw_); jw.kv("up", (uint32_t)nowMs());
      if (repo_.length()) jw.kv("repo", repo_);
      if (about_.length()) jw.kv("about", about_);
      jw.kv("time", (uint32_t)time()); jw.kv("clients", (int32_t)clients());
      if (infoFill) infoFill(jw); else { jw.kv("chip", "native"); jw.kv("heap", (uint32_t)0); }
    });
  }
  if (!strcmp(cmd, "reboot")) { reply([&](JsonWriter& jw) { jw.kv("ok", true); }); requestReboot(RebootReason::Client); return; }
  if (!strcmp(cmd, "pin.set")) {
    const char* pin = DOC["pin"];
    if (!pin) return sendErr(c.slot, 7, "pin required", "pin.set");
    bool ok = auth_.setPinRuntime(pin);
    reply([&](JsonWriter& jw) { jw.kv("ok", ok); });
    return;
  }
  if (!strcmp(cmd, "revoke")) {
    auth_.revoke();
    reply([&](JsonWriter& jw) { jw.kv("ok", true); });
    for (auto& o : clients_) if (o.used && o.slot != c.slot && o.tr) o.tr->close(o.slot);
    return;
  }
  const char* cap = nullptr;
  if (!strncmp(cmd, "wifi.", 5)) cap = "wifi";
  else if (!strcmp(cmd, "ota.url")) cap = "otaurl";
  else if (!strncmp(cmd, "ota.", 4)) cap = "ota";
  if (cap && !hasCap(cap)) return sendErr(c.slot, 8, "capability not available", cmd);
  if (sysHook && sysHook(c.slot, cmd, doc)) return;
  sendErr(c.slot, cap ? 8 : 7, cap ? "capability not available" : "unknown cmd", cmd);
}

// ---- time / reboot / loop -----------------------------------------------------------
uint32_t Core::time() const { return timeValid_ ? unixAtSync_ + (nowMs() - msAtSync_) / 1000 : 0; }

void Core::setTime(uint32_t unix, bool authoritative) {
  if (timeAuthoritative_ && !authoritative) return;
  unixAtSync_ = unix; msAtSync_ = nowMs(); timeValid_ = true; timeAuthoritative_ = authoritative;
  clockAt_ = 0;
}

void Core::requestReboot(RebootReason r, uint32_t delayMs) {
  if (rebootPending_) return;
  rebootPending_ = true; rebootReason_ = r; rebootAt_ = nowMs() + delayMs;
}

void Core::loop() {
  uint32_t now = nowMs();
  for (auto t : trs_) t->loop();
  for (auto u : uis_) u->loop(now);
  if (timeValid_ && (!clockAt_ || (uint32_t)(now - clockAt_) >= 60000u)) { clockAt_ = now ? now : 1; for (auto u : uis_) u->tickClocks(time()); }
  for (auto& c : clients_) if (c.used && c.authed && (uint32_t)(now - c.lastFlush) >= ESPFACE_FLUSH_MS) flush(c);
  if (rebootPending_ && (int32_t)(now - rebootAt_) >= 0) {
    rebootPending_ = false;
    if (onReboot_) onReboot_(rebootReason_);
    if (rebootFn) rebootFn();
  }
}

}  // namespace espface
