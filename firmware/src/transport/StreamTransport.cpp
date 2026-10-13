#include "StreamTransport.h"
#include "../core/Core.h"
#include <stdio.h>

namespace espface {

void StreamTransport::begin() {
  if (begun_) return;
  begun_ = true;
  lf_.reset();
  if (openOnBegin_) openSlot();
}

bool StreamTransport::openSlot() {
  if (slot_ >= 0) return true;
  int s = core_->onOpen(this);
  if (s < 0) { rawErr(9, "too many clients"); return false; }
  slot_ = s; lastRx_ = nowMs();
  return true;
}

void StreamTransport::endSession() {
  closePending_ = false;
  if (slot_ < 0) return;
  int s = slot_; slot_ = -1;
  core_->onClose((uint8_t)s);
}

void StreamTransport::rawErr(int code, const char* msg) {
  char b[96];
  int n = snprintf(b, sizeof b, "{\"t\":\"err\",\"code\":%d,\"msg\":\"%s\"}\n", code, msg);
  if (n > 0) io_.write((const uint8_t*)b, (size_t)n);
}

void StreamTransport::loop() {
  if (closePending_) endSession();
  size_t budget = 4 * ESPFACE_MAX_MSG;   // bytes per loop, keeps a flooding stream from starving the core
  while (budget-- && io_.available() > 0) {
    int b = io_.read();
    if (b < 0) break;
    LineFramer::Result r = lf_.feed((uint8_t)b);
    if (r == LineFramer::None) continue;
    lastRx_ = nowMs();
    if (r == LineFramer::Oversize) {
      if (slot_ >= 0) core_->sendErr((uint8_t)slot_, 2, "message too large"); else rawErr(2, "message too large");
      continue;
    }
    if (slot_ >= 0 && strstr(lf_.data(), "\"t\":\"hello\"")) endSession();   // a new client on the same wire
    if (!openSlot()) continue;
    core_->onMessage((uint8_t)slot_, lf_.data(), lf_.len());
    if (closePending_) endSession();
  }
  if (slot_ >= 0 && idleMs_ && (uint32_t)(nowMs() - lastRx_) >= idleMs_) endSession();
}

bool StreamTransport::sendFrame(uint8_t slot, const char* data, size_t len, bool, bool last) {
  if ((int)slot != slot_) return false;
  if (len) io_.write((const uint8_t*)data, len);
  if (last) io_.write((const uint8_t*)"\n", 1);
  return true;
}

void StreamTransport::close(uint8_t slot) { if ((int)slot == slot_) closePending_ = true; }

}  // namespace espface
