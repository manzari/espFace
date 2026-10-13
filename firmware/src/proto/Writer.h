#pragma once
#include "../core/Platform.h"
#include "../core/Value.h"

namespace espface {

// Byte sink; end() marks the end of one message.
class Sink {
 public:
  virtual ~Sink() {}
  virtual void write(const char* data, size_t len) = 0;
  virtual void end() {}
};

class StrSink : public Sink {
 public:
  explicit StrSink(Str& out) : out_(out) {}
  void write(const char* data, size_t len) override { for (size_t i = 0; i < len; i++) out_ += data[i]; }
 private:
  Str& out_;
};

// Minimal streaming JSON writer with automatic commas. Depth up to 32.
class JsonWriter {
 public:
  explicit JsonWriter(Sink& sink) : sink_(sink) {}
  ~JsonWriter() { flush(); }

  void beginObj() { sep(); put('{'); push(); }
  void endObj() { pop(); put('}'); }
  void beginArr() { sep(); put('['); push(); }
  void endArr() { pop(); put(']'); }
  void key(const char* k) { sep(); str_(k); put(':'); keyPending_ = true; }
  void str(const char* v) { sep(); str_(v ? v : ""); }
  void str(const Str& v) { str(v.c_str()); }
  void num(float v) { sep(); char b[24]; fmtFloat(v, b, sizeof b); puts_(b); }
  void integer(int32_t v) { sep(); char b[16]; snprintf(b, sizeof b, "%ld", (long)v); puts_(b); }
  void uinteger(uint32_t v) { sep(); char b[16]; snprintf(b, sizeof b, "%lu", (unsigned long)v); puts_(b); }
  void boolean(bool v) { sep(); puts_(v ? "true" : "false"); }
  void null() { sep(); puts_("null"); }
  void raw(const char* json) { sep(); puts_(json); }
  void value(const Value& v) {
    switch (v.type) {
      case Value::Null: null(); break;
      case Value::Bool: boolean(v.b); break;
      case Value::Int: integer(v.i); break;
      case Value::Float: num(v.f); break;
      case Value::String: str(v.s); break;
      case Value::Raw: raw(v.s.c_str()); break;
      case Value::Pair: beginArr(); integer(v.x); integer(v.y); endArr(); break;
    }
  }
  // convenience: "key":value
  void kv(const char* k, const char* v) { key(k); str(v); }
  void kv(const char* k, const Str& v) { key(k); str(v); }
  void kv(const char* k, bool v) { key(k); boolean(v); }
  void kv(const char* k, int32_t v) { key(k); integer(v); }
  void kv(const char* k, uint32_t v) { key(k); uinteger(v); }
  void kv(const char* k, float v) { key(k); num(v); }
  void kv(const char* k, const Value& v) { key(k); value(v); }

  void flush() { if (n_) { sink_.write(buf_, n_); n_ = 0; } }

 private:
  void push() { depth_++; first_ = true; keyPending_ = false; }
  void pop() { depth_--; first_ = false; keyPending_ = false; }
  void sep() {
    if (keyPending_) { keyPending_ = false; return; }
    if (!first_) put(',');
    first_ = false;
  }
  void put(char c) { if (n_ >= sizeof buf_) flush(); buf_[n_++] = c; }
  void puts_(const char* s) { while (*s) put(*s++); }
  void str_(const char* s) {
    put('"');
    for (const unsigned char* p = (const unsigned char*)s; *p; p++) {
      unsigned char c = *p;
      switch (c) {
        case '"': puts_("\\\""); break;
        case '\\': puts_("\\\\"); break;
        case '\n': puts_("\\n"); break;
        case '\r': puts_("\\r"); break;
        case '\t': puts_("\\t"); break;
        default:
          if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); puts_(b); }
          else put((char)c);
      }
    }
    put('"');
  }

  Sink& sink_;
  char buf_[128];
  size_t n_ = 0;
  int depth_ = 0;
  bool first_ = true;
  bool keyPending_ = false;
};

}  // namespace espface
