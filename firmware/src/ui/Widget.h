#pragma once
#include <vector>
#include "../core/Platform.h"
#include "../core/Value.h"

namespace espface {

enum class WType : uint8_t {
  Label, Button, Switch, Slider, Number, Text, Select, Gauge, Progress, Led, Chart, Header, Group, Page, Row, Spacer,
  Textarea, Flags, Color, Datetime, Joystick, Dpad, Display, Log, Table, Image, Stream, Clock, Map, Textblock,
  Unknown
};

enum class PKey : uint8_t {
  lbl, grp, page, row, size, sq, dis, vis, hint, icon, ro, color, hold, on, off, min, max, step, unit, spin, maxlen,
  secret, re, opts, style, zones, series, win, legend, vals, fold, fmt, center, rows, cap, digits, rgb, mode, src, text,
  exp, cols, zoom, _count
};

const char* wtypeName(WType t);
WType wtypeFromName(const char* n);
const char* pkeyName(PKey k);
PKey pkeyFromName(const char* n);

// What kind of value a widget type carries.
enum class VKind : uint8_t { None, Bool, Num, Int, Str, Pair, BoolOrInt, NumOrStr, Rows };
VKind valueKind(WType t);

struct Prop {
  PKey k;
  Value v;
};

struct Widget {
  enum Flag : uint8_t { HasValue = 1, Persist = 2, Ro = 4, Dis = 8, Hidden = 16, Restored = 32, Output = 64 };

  Str id;
  WType ty = WType::Label;
  uint8_t flags = 0;
  uint8_t dirty = 0;      // bit per client slot: value changed since last flush
  int8_t pageIdx = -1;    // index among pages this widget belongs to, -1 = first page
  uint8_t nopts = 0;      // option count for select/flags
  Value val;
  std::vector<Prop> props;

  const Prop* find(PKey k) const { for (auto& p : props) if (p.k == k) return &p; return nullptr; }
  Prop* find(PKey k) { for (auto& p : props) if (p.k == k) return &p; return nullptr; }
  void setProp(PKey k, const Value& v) { if (Prop* p = find(k)) p->v = v; else props.push_back({k, v}); }
  float numProp(PKey k, float def) const { const Prop* p = find(k); return p && p->v.isNum() ? p->v.asFloat() : def; }
  bool has(Flag f) const { return flags & f; }
  void set(Flag f, bool on) { if (on) flags |= f; else flags &= ~f; }
};

}  // namespace espface
