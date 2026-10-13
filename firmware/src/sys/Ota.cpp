#include "Ota.h"
#include <ArduinoJson.h>
#include "../core/Core.h"

namespace espface {

#define DOC (*(JsonDocument*)doc)

static bool validMd5(const char* s) {
  if (!s || strlen(s) != 32) return false;
  for (const char* p = s; *p; p++) if (!((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f'))) return false;
  return true;
}

void Ota::begin(Core* core, OtaBackend* backend, Store* store) { core_ = core; be_ = backend; store_ = store; }

bool Ota::handleSys(uint8_t slot, const char* cmd, void* doc) {
  auto reply = [&](bool ok, const char* msg) {
    core_->send(slot, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", cmd); jw.kv("ok", ok); if (msg) jw.kv("msg", msg); jw.endObj(); });
  };
  if (!strcmp(cmd, "ota.begin")) {
    if (active_) { core_->sendErr(slot, 9, "ota in progress", cmd); return true; }
    long size = DOC["size"] | 0L;
    const char* md5 = DOC["md5"];
    const char* kind = DOC["kind"] | "fw";
    if (size <= 0 || !validMd5(md5) || strcmp(kind, "fw")) { core_->sendErr(slot, 7, "size and md5 required", cmd); return true; }
    if (!start(slot, (size_t)size, md5)) { core_->sendErr(slot, 10, be_ ? be_->error() : "no backend", cmd); return true; }
    reply(true, nullptr);
    return true;
  }
  if (!strcmp(cmd, "ota.abort")) { abort(); reply(true, nullptr); return true; }
  if (!strcmp(cmd, "ota.url")) {
    if (active_) { core_->sendErr(slot, 9, "ota in progress", cmd); return true; }
    const char* url = DOC["url"];
    if (!url || (strncmp(url, "http://", 7) && strncmp(url, "https://", 8))) { core_->sendErr(slot, 7, "bad url", cmd); return true; }
    if (!urlFetch) { core_->sendErr(slot, 10, "url download not supported", cmd); return true; }
    reply(true, nullptr);
    logf("ota from %s", url);
    urlFetch(url);   // blocking; reports via ota.progress / ota.done
    return true;
  }
  return false;
}

bool Ota::start(int slot, size_t size, const char* md5) {
  if (active_ || !be_) return false;
  if (!be_->begin(size, md5)) return false;
  active_ = true; slot_ = slot; size_ = size; got_ = 0; lastPct_ = -1;
  lastData_ = nowMs(); lastPush_ = lastData_ - 500;   // first progress push goes out immediately
  return true;
}

bool Ota::feed(const uint8_t* data, size_t len) {
  if (!active_) return false;
  size_t w = be_->write(data, len);
  got_ += w; lastData_ = nowMs();
  if (w != len) { fail(be_->error()); return false; }
  progress(false);
  return true;
}

bool Ota::finish() {
  if (!active_) return false;
  bool ok = be_->end();
  if (ok && store_) store_->putStr("rr", "ota");
  Str err = ok ? "" : be_->error();
  active_ = false;
  done(ok, ok ? nullptr : err.c_str());
  if (ok) core_->requestReboot(RebootReason::Ota, 1000);
  return ok;
}

void Ota::fail(const char* msg) {
  Str m = msg ? msg : "update failed";
  if (active_) be_->abort();
  active_ = false;
  done(false, m.c_str());
}

void Ota::abort() {
  if (!active_) return;
  be_->abort();
  active_ = false;
}

bool Ota::onBinary(uint8_t slot, const uint8_t* data, size_t len) {
  if (!active_ || slot_ != (int)slot) return false;
  if (!feed(data, len)) return true;
  if (got_ >= size_) finish();
  return true;
}

void Ota::onClose(uint8_t slot) {
  if (active_ && slot_ == (int)slot) { logf("ota client left, aborting"); abort(); }
}

void Ota::loop() {
  if (active_ && timeoutMs_ && (uint32_t)(nowMs() - lastData_) >= timeoutMs_) fail("timeout");
}

void Ota::progress(bool force) {
  int pct = size_ ? (int)((uint64_t)got_ * 100 / size_) : (force ? 100 : 0);
  if (pct > 100) pct = 100;
  if (!force && (pct == lastPct_ || (uint32_t)(nowMs() - lastPush_) < 500)) return;
  lastPct_ = pct; lastPush_ = nowMs();
  for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) {
    Client* c = core_->client(i);
    if (c && c->used && c->authed) core_->send(i, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "ota.progress"); jw.kv("pct", (int32_t)pct); jw.endObj(); });
  }
}

void Ota::done(bool ok, const char* msg) {
  if (ok) progress(true);
  for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) {
    Client* c = core_->client(i);
    if (c && c->used && c->authed) core_->send(i, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "sys"); jw.kv("cmd", "ota.done"); jw.kv("ok", ok); if (msg) jw.kv("msg", msg); jw.endObj(); });
  }
  logf(ok ? "ota ok, rebooting" : "ota failed: %s", msg ? msg : "");
}

}  // namespace espface
