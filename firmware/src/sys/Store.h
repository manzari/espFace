#pragma once
#include "../core/Platform.h"
#include "../core/Value.h"

namespace espface {

// Key/value persistence. Keys are at most 15 characters (NVS limit).
class Store {
 public:
  virtual ~Store() {}
  virtual bool getStr(const char* key, Str& out) = 0;
  virtual bool putStr(const char* key, const Str& v) = 0;
  virtual bool remove(const char* key) = 0;
  virtual void clear() = 0;

  bool getValue(const char* key, Value& out);
  bool putValue(const char* key, const Value& v);
};

// In-memory store for tests and as fallback.
class MemStore : public Store {
 public:
  bool getStr(const char* key, Str& out) override;
  bool putStr(const char* key, const Str& v) override;
  bool remove(const char* key) override;
  void clear() override { n_ = 0; }
  size_t size() const { return n_; }
 private:
  enum { MAX = 64 };
  struct E { Str k, v; } e_[MAX];
  size_t n_ = 0;
};

}  // namespace espface
