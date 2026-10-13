#include "Session.h"
#include "../util/Hmac.h"

namespace espface {

void Auth::begin(Store* store) {
  store_ = store;
  Str p;
  if (store_ && store_->getStr("pin", p)) pin_ = p;
  loadTokens();
}

void Auth::setPin(const char* pin, bool force) {
  Str stored;
  bool haveStored = store_ && store_->getStr("pin", stored);
  if (haveStored && !force) { pin_ = stored; return; }
  pin_ = pin ? pin : "";
  if (store_) { if (pin_.length()) store_->putStr("pin", pin_); else store_->remove("pin"); }
}

bool Auth::setPinRuntime(const char* pin) {
  size_t n = pin ? strlen(pin) : 0;
  if (n && (n < 4 || n > 32)) return false;
  pin_ = pin ? pin : "";
  if (store_) { if (n) store_->putStr("pin", pin_); else store_->remove("pin"); }
  revoke();
  return true;
}

void Auth::loadTokens() {
  ntok_ = 0;
  if (!store_) return;
  for (uint8_t i = 0; i < MaxTokens; i++) {
    char k[4] = {'t', (char)('0' + i), 0};
    Str t;
    if (store_->getStr(k, t) && t.length() == 32) tokens_[ntok_++] = t;
  }
}

bool Auth::validToken(const char* tok) {
  if (!tok || strlen(tok) != 32) return false;
  for (uint8_t i = 0; i < ntok_; i++) if (constantTimeEq(tokens_[i].c_str(), tok, 32)) return true;
  return false;
}

Str Auth::issueToken() {
  uint8_t raw[16]; char hex[33];
  randomBytes(raw, 16); toHex(raw, 16, hex);
  if (ntok_ >= MaxTokens) { for (uint8_t i = 1; i < MaxTokens; i++) tokens_[i - 1] = tokens_[i]; ntok_ = MaxTokens - 1; }
  tokens_[ntok_++] = hex;
  if (store_) for (uint8_t i = 0; i < ntok_; i++) { char k[4] = {'t', (char)('0' + i), 0}; store_->putStr(k, tokens_[i]); }
  return Str(hex);
}

void Auth::revoke() {
  ntok_ = 0;
  if (store_) for (uint8_t i = 0; i < MaxTokens; i++) { char k[4] = {'t', (char)('0' + i), 0}; store_->remove(k); }
}

uint32_t Auth::lockLeft(uint32_t now) const {
  if (!lockUntil_) return 0;
  int32_t d = (int32_t)(lockUntil_ - now);
  return d > 0 ? (uint32_t)((d + 999) / 1000) : 0;
}

void Auth::makeNonce(char out[33]) { uint8_t raw[16]; randomBytes(raw, 16); toHex(raw, 16, out); }

bool Auth::check(const char* mac, const char* nonce, const char* deviceId, const char* pinOverride, uint32_t now, uint8_t& left, uint32_t& lock) {
  left = 0; lock = lockLeft(now);
  if (lock) return false;
  lockUntil_ = 0;
  const char* pin = pinOverride ? pinOverride : pin_.c_str();
  char expect[65];
  pinMac(pin, nonce, deviceId, expect);
  bool ok = mac && strlen(mac) == 64 && constantTimeEq(mac, expect, 64);
  if (ok) { failed_ = 0; return true; }
  if (++failed_ >= LockAfter) { failed_ = 0; lockUntil_ = now + LockSeconds * 1000UL; lock = LockSeconds; return false; }
  left = LockAfter - failed_;
  return false;
}

}  // namespace espface
