#pragma once
#include "../core/Platform.h"
#include <functional>
#include <stdlib.h>

namespace espface {

// GATT packet layout: [seq:1][flags:1][payload]. flags bit0 = last chunk of the message, bit1 = first chunk.
// seq counts packets per connection and direction and wraps 255 -> 0.
enum : uint8_t { BLE_FLAG_LAST = 1, BLE_FLAG_FIRST = 2 };

// Device -> client: collects message bytes (delivered in any number of frames) into packets of mtu-3 payload.
class BleChunker {
 public:
  explicit BleChunker(uint16_t mtu = 23) { setMtu(mtu); }
  void setMtu(uint16_t mtu) { if (mtu < 23) mtu = 23; if (mtu > ESPFACE_BLE_MTU) mtu = ESPFACE_BLE_MTU; max_ = (size_t)mtu - 3; }
  size_t payloadMax() const { return max_; }
  uint8_t seq() const { return seq_; }
  void reset() { n_ = 0; first_ = true; }

  // Feed one frame of a message; `last` ends the message. emit(packet, len) sends one packet; false aborts.
  bool frame(const char* data, size_t len, bool last, const std::function<bool(const uint8_t*, size_t)>& emit) {
    while (len) {
      size_t take = max_ - n_; if (take > len) take = len;
      memcpy(buf_ + 2 + n_, data, take); n_ += take; data += take; len -= take;
      if (n_ == max_ && (len || !last)) { if (!flush(false, emit)) return false; }
    }
    if (last) return flush(true, emit);
    return true;
  }

 private:
  bool flush(bool last, const std::function<bool(const uint8_t*, size_t)>& emit) {
    buf_[0] = seq_++;
    buf_[1] = (uint8_t)((last ? BLE_FLAG_LAST : 0) | (first_ ? BLE_FLAG_FIRST : 0));
    bool ok = emit(buf_, 2 + n_);
    n_ = 0; first_ = last;
    return ok;
  }
  uint8_t buf_[ESPFACE_BLE_MTU];
  size_t max_ = 20, n_ = 0;
  uint8_t seq_ = 0;
  bool first_ = true;
};

// Client -> device: rebuilds messages. A seq gap or a stray continuation drops the partial message,
// a repeated seq is ignored, an oversize message is skipped up to its last chunk.
class BleReassembler {
 public:
  enum Result : uint8_t { None, Message, Dropped, Oversize };
  explicit BleReassembler(size_t cap = ESPFACE_MAX_MSG) : cap_(cap), buf_((char*)malloc(cap + 1)) {}
  ~BleReassembler() { free(buf_); }
  BleReassembler(const BleReassembler&) = delete;
  BleReassembler& operator=(const BleReassembler&) = delete;

  Result feed(const uint8_t* pkt, size_t n) {
    if (n < 2 || !buf_) return Dropped;
    uint8_t seq = pkt[0], flags = pkt[1];
    if (flags & BLE_FLAG_FIRST) { open_ = true; skip_ = false; n_ = 0; }
    else if (skip_) { if (seq == expect_) { expect_++; if (flags & BLE_FLAG_LAST) skip_ = false; } return None; }
    else if (!open_) return Dropped;
    else if (seq == (uint8_t)(expect_ - 1)) return None;                 // duplicate
    else if (seq != expect_) { open_ = false; n_ = 0; return Dropped; }  // gap
    expect_ = (uint8_t)(seq + 1);
    size_t len = n - 2;
    if (n_ + len > cap_) { open_ = false; skip_ = !(flags & BLE_FLAG_LAST); n_ = 0; return Oversize; }
    memcpy(buf_ + n_, pkt + 2, len); n_ += len;
    if (flags & BLE_FLAG_LAST) { open_ = false; buf_[n_] = 0; ready_ = n_; n_ = 0; return Message; }
    return None;
  }
  const char* data() const { return buf_; }
  size_t len() const { return ready_; }
  bool partial() const { return open_; }
  void reset() { open_ = skip_ = false; n_ = ready_ = 0; }

 private:
  size_t cap_;
  char* buf_;
  size_t n_ = 0, ready_ = 0;
  uint8_t expect_ = 0;
  bool open_ = false, skip_ = false;
};

}  // namespace espface
