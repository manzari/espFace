#pragma once
#include "../core/Platform.h"
#include "../core/Value.h"
#include <vector>

namespace espface {

// Key/value persistence. Keys and namespace names are at most 15 characters (NVS limit).
class Store {
 public:
  virtual ~Store() {}
  virtual bool getStr(const char* key, Str& out) = 0;
  virtual bool putStr(const char* key, const Str& v) = 0;
  virtual bool remove(const char* key) = 0;
  virtual void clear() = 0;
  // Another namespace of the same backend, owned by the caller.
  virtual Store* open(const char* ns) = 0;

  bool getValue(const char* key, Value& out);
  bool putValue(const char* key, const Value& v);
};

// In-memory store for tests; namespaces opened from it share its entries.
class MemStore : public Store {
 public:
  MemStore() {}
  MemStore(const MemStore&) = delete;
  MemStore& operator=(const MemStore&) = delete;
  bool getStr(const char* key, Str& out) override;
  bool putStr(const char* key, const Str& v) override;
  bool remove(const char* key) override;
  void clear() override;
  Store* open(const char* ns) override { return new MemStore(root_, ns); }
 private:
  MemStore(MemStore* root, const char* ns) : root_(root), ns_(ns) {}
  enum { MAX = 64 };
  struct E { Str ns, k, v; };
  int find(const char* key) const;
  MemStore* root_ = this;
  Str ns_;
  std::vector<E> e_;
};

}  // namespace espface
