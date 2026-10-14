#include "Store.h"
#include <stdlib.h>

namespace espface {

bool Store::getValue(const char* key, Value& out) {
  Str s;
  if (!getStr(key, s) || s.length() < 1) return false;
  const char* p = s.c_str() + 1;
  switch (s.c_str()[0]) {
    case 'b': out = Value::ofBool(p[0] == '1'); return true;
    case 'i': out = Value::ofInt((int32_t)strtol(p, nullptr, 10)); return true;
    case 'f': out = Value::ofFloat((float)strtod(p, nullptr)); return true;
    case 's': out = Value::ofStr(p); return true;
    case 'p': { int x = 0, y = 0; sscanf(p, "%d,%d", &x, &y); out = Value::ofPair((int16_t)x, (int16_t)y); return true; }
  }
  return false;
}

bool Store::putValue(const char* key, const Value& v) {
  char b[48];
  Str s;
  switch (v.type) {
    case Value::Bool: s = v.b ? "b1" : "b0"; break;
    case Value::Int: snprintf(b, sizeof b, "i%ld", (long)v.i); s = b; break;
    case Value::Float: { char f[24]; fmtFloat(v.f, f, sizeof f); s = "f"; s += f; break; }
    case Value::String: s = "s"; s += v.s.c_str(); break;
    case Value::Pair: snprintf(b, sizeof b, "p%d,%d", v.x, v.y); s = b; break;
    default: return remove(key);
  }
  return putStr(key, s);
}

int MemStore::find(const char* key) const {
  const auto& e = root_->e_;
  for (size_t i = 0; i < e.size(); i++) if (e[i].ns == ns_ && strEq(e[i].k, key)) return (int)i;
  return -1;
}

bool MemStore::getStr(const char* key, Str& out) {
  int i = find(key);
  if (i < 0) return false;
  out = root_->e_[i].v; return true;
}

bool MemStore::putStr(const char* key, const Str& v) {
  int i = find(key);
  if (i >= 0) { root_->e_[i].v = v; return true; }
  if (root_->e_.size() >= MAX) return false;
  root_->e_.push_back({ns_, Str(key), v});
  return true;
}

bool MemStore::remove(const char* key) {
  int i = find(key);
  if (i < 0) return false;
  root_->e_.erase(root_->e_.begin() + i); return true;
}

void MemStore::clear() {
  auto& e = root_->e_;
  for (size_t i = e.size(); i-- > 0;) if (e[i].ns == ns_) e.erase(e.begin() + i);
}

}  // namespace espface
