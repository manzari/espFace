#pragma once
#include "Store.h"
#ifdef ARDUINO
#include <Preferences.h>

namespace espface {

class NvsStore : public Store {
 public:
  void begin(const char* ns = "espface") { prefs_.begin(ns, false); }
  bool getStr(const char* key, Str& out) override { if (!prefs_.isKey(key)) return false; out = prefs_.getString(key, ""); return true; }
  bool putStr(const char* key, const Str& v) override { return prefs_.putString(key, v) > 0 || v.length() == 0; }
  bool remove(const char* key) override { return prefs_.remove(key); }
  void clear() override { prefs_.clear(); }
  Store* open(const char* ns) override { NvsStore* s = new NvsStore; s->begin(ns); return s; }
 private:
  Preferences prefs_;
};

}  // namespace espface
#endif
