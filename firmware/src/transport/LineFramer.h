#pragma once
#include "../core/Platform.h"
#include <stdlib.h>

namespace espface {

// Splits a byte stream into '\n'-terminated lines: '\r' is dropped, empty lines are skipped,
// a line longer than cap is discarded and reported once as Oversize at its newline.
class LineFramer {
 public:
  enum Result : uint8_t { None, Line, Oversize };
  explicit LineFramer(size_t cap = ESPFACE_MAX_MSG) : cap_(cap), buf_((char*)malloc(cap + 1)) {}
  ~LineFramer() { free(buf_); }
  LineFramer(const LineFramer&) = delete;
  LineFramer& operator=(const LineFramer&) = delete;

  Result feed(uint8_t b) {
    if (b == '\r' || !buf_) return None;
    if (b == '\n') {
      if (over_) { over_ = false; n_ = 0; return Oversize; }
      if (!n_) return None;
      buf_[n_] = 0; ready_ = n_; n_ = 0;
      return Line;
    }
    if (over_) return None;
    if (n_ >= cap_) { over_ = true; n_ = 0; return None; }
    buf_[n_++] = (char)b;
    return None;
  }
  // Valid until the next feed() that returns Line.
  const char* data() const { return buf_; }
  size_t len() const { return ready_; }
  void reset() { n_ = 0; ready_ = 0; over_ = false; }

 private:
  size_t cap_;
  char* buf_;
  size_t n_ = 0, ready_ = 0;
  bool over_ = false;
};

}  // namespace espface
