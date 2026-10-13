#pragma once
#include "Platform.h"

namespace espface {

// Small variant for widget values and props.
struct Value {
  enum Type : uint8_t { Null, Bool, Int, Float, String, Pair, Raw };
  Type type = Null;
  bool b = false;
  int32_t i = 0;
  float f = 0;
  int16_t x = 0, y = 0;
  Str s;  // String and Raw (Raw = pre-built JSON emitted verbatim)

  Value() {}
  static Value ofBool(bool v) { Value r; r.type = Bool; r.b = v; return r; }
  static Value ofInt(int32_t v) { Value r; r.type = Int; r.i = v; return r; }
  static Value ofFloat(float v) { Value r; r.type = Float; r.f = v; return r; }
  static Value ofStr(const char* v) { Value r; r.type = String; r.s = v; return r; }
  static Value ofStr(const Str& v) { Value r; r.type = String; r.s = v; return r; }
  static Value ofPair(int16_t px, int16_t py) { Value r; r.type = Pair; r.x = px; r.y = py; return r; }
  static Value ofRaw(const Str& json) { Value r; r.type = Raw; r.s = json; return r; }

  bool isNull() const { return type == Null; }
  bool isNum() const { return type == Int || type == Float; }
  bool asBool() const { return type == Bool ? b : (type == Int ? i != 0 : (type == Float ? f != 0 : false)); }
  float asFloat() const { return type == Float ? f : (type == Int ? (float)i : (type == Bool ? (b ? 1.f : 0.f) : 0.f)); }
  int32_t asInt() const { return type == Int ? i : (type == Float ? (int32_t)f : (type == Bool ? (b ? 1 : 0) : 0)); }
  const Str& asStr() const { return s; }

  bool equals(const Value& o) const {
    if (type != o.type) return false;
    switch (type) {
      case Null: return true;
      case Bool: return b == o.b;
      case Int: return i == o.i;
      case Float: return f == o.f;
      case String: case Raw: return s == o.s;
      case Pair: return x == o.x && y == o.y;
    }
    return false;
  }
};

}  // namespace espface
