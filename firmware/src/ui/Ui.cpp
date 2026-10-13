#include "Ui.h"
#include <math.h>

namespace espface {

// ---- helpers --------------------------------------------------------------
static Str jsonStrArray(const std::vector<const char*>& items) {
  Str out; StrSink sink(out);
  { JsonWriter jw(sink); jw.beginArr(); for (auto s : items) jw.str(s); jw.endArr(); }
  return out;
}

static void appendToRawArray(Widget& w, PKey k, const Str& itemJson) {
  Prop* p = w.find(k);
  if (!p) { Str a = "["; a += itemJson.c_str(); a += "]"; w.setProp(k, Value::ofRaw(a)); return; }
  Str a = p->v.s;
  if (a.length() >= 2 && a.c_str()[a.length() - 1] == ']') {
    Str b; for (size_t i = 0; i + 1 < a.length(); i++) b += a.c_str()[i];
    if (b.length() > 1) b += ",";
    b += itemJson.c_str(); b += "]";
    p->v.s = b;
  }
}

// ---- builder --------------------------------------------------------------
WidgetRef Ui::push_(WType ty, const char* id, const char* lbl) {
  Widget w;
  w.id = id; w.ty = ty;
  if (lbl) w.setProp(PKey::lbl, Value::ofStr(lbl));
  VKind k = valueKind(ty);
  if (k != VKind::None) {
    w.set(Widget::HasValue, true);
    switch (k) {
      case VKind::Bool: w.val = Value::ofBool(false); break;
      case VKind::Num: w.val = Value::ofFloat(0); break;
      case VKind::Int: case VKind::BoolOrInt: w.val = Value::ofInt(0); break;
      case VKind::Str: case VKind::NumOrStr: w.val = Value::ofStr(""); break;
      case VKind::Pair: w.val = Value::ofPair(0, 0); break;
      case VKind::Rows: w.val = Value::ofRaw("[]"); break;
      default: break;
    }
  }
  switch (ty) {
    case WType::Label: case WType::Gauge: case WType::Progress: case WType::Display: case WType::Led:
    case WType::Clock: case WType::Table: case WType::Map: w.set(Widget::Output, true); break;
    default: break;
  }
  if (ty != WType::Page && curPage_ >= 0) { w.pageIdx = curPage_; w.setProp(PKey::page, Value::ofStr(w_[pages_[curPage_]].id)); }
  w_.push_back(w);
  return WidgetRef(this, (uint16_t)(w_.size() - 1));
}

WidgetRef Ui::page(const char* id, const char* lbl) {
  WidgetRef r = push_(WType::Page, id, lbl);
  pages_.push_back(r.index());
  curPage_ = (int8_t)(pages_.size() - 1);
  return r;
}
WidgetRef Ui::header(const char* lbl) { char id[16]; snprintf(id, sizeof id, "h%u", (unsigned)w_.size()); return push_(WType::Header, id, lbl); }
WidgetRef Ui::group(const char* id, const char* lbl) { return push_(WType::Group, id, lbl); }
WidgetRef Ui::row(const char* id) { return push_(WType::Row, id, nullptr); }
WidgetRef Ui::spacer(const char* id, float w, int h) { return push_(WType::Spacer, id, nullptr).size(w, h); }
WidgetRef Ui::label(const char* id, const char* lbl, const char* unit) { WidgetRef r = push_(WType::Label, id, lbl); if (unit) r.unit(unit); return r; }
WidgetRef Ui::button(const char* id, const char* lbl) { return push_(WType::Button, id, lbl); }
WidgetRef Ui::sw(const char* id, const char* lbl) { return push_(WType::Switch, id, lbl); }
WidgetRef Ui::slider(const char* id, const char* lbl, float min, float max, float step, const char* unit) {
  WidgetRef r = push_(WType::Slider, id, lbl).range(min, max).step(step); if (unit) r.unit(unit); w_[r.index()].val = Value::ofFloat(min); return r;
}
WidgetRef Ui::number(const char* id, const char* lbl, float min, float max, float step, const char* unit) {
  WidgetRef r = push_(WType::Number, id, lbl).range(min, max).step(step); if (unit) r.unit(unit); w_[r.index()].val = Value::ofFloat(min); return r;
}
WidgetRef Ui::text(const char* id, const char* lbl, int maxlen) { return push_(WType::Text, id, lbl).maxlen(maxlen); }
WidgetRef Ui::select(const char* id, const char* lbl, const std::vector<const char*>& opts) {
  WidgetRef r = push_(WType::Select, id, lbl);
  w_[r.index()].setProp(PKey::opts, Value::ofRaw(jsonStrArray(opts)));
  w_[r.index()].nopts = (uint8_t)opts.size();
  return r;
}
WidgetRef Ui::gauge(const char* id, const char* lbl, float min, float max, const char* unit) {
  WidgetRef r = push_(WType::Gauge, id, lbl).range(min, max); if (unit) r.unit(unit); return r;
}
WidgetRef Ui::progress(const char* id, const char* lbl, float min, float max) { return push_(WType::Progress, id, lbl).range(min, max); }
WidgetRef Ui::led(const char* id, const char* lbl, const char* color) { WidgetRef r = push_(WType::Led, id, lbl); if (color) r.color(color); w_[r.index()].val = Value::ofBool(false); return r; }
WidgetRef Ui::chart(const char* id, const char* lbl, int winSeconds, const char* unit) {
  WidgetRef r = push_(WType::Chart, id, lbl); w_[r.index()].setProp(PKey::win, Value::ofInt(winSeconds)); if (unit) r.unit(unit); return r;
}
WidgetRef Ui::textblock(const char* id, const char* text) { WidgetRef r = push_(WType::Textblock, id, nullptr); w_[r.index()].setProp(PKey::text, Value::ofStr(text)); return r; }
WidgetRef Ui::log(const char* id, const char* lbl, int cap, int rows) {
  WidgetRef r = push_(WType::Log, id, lbl);
  w_[r.index()].setProp(PKey::cap, Value::ofInt(cap)); w_[r.index()].setProp(PKey::rows, Value::ofInt(rows));
  return r;
}
WidgetRef Ui::add(WType ty, const char* id, const char* lbl) { return push_(ty, id, lbl); }

// ---- WidgetRef --------------------------------------------------------------
WidgetRef& WidgetRef::flag(PKey k, bool on) { ui_->w_[idx_].setProp(k, Value::ofBool(on)); return *this; }
WidgetRef& WidgetRef::strp(PKey k, const char* v) { if (v) ui_->w_[idx_].setProp(k, Value::ofStr(v)); return *this; }
WidgetRef& WidgetRef::nump(PKey k, float v) { ui_->w_[idx_].setProp(k, Value::ofFloat(v)); return *this; }
WidgetRef& WidgetRef::group(const char* id) { return strp(PKey::grp, id); }
WidgetRef& WidgetRef::row(const char* id) { return strp(PKey::row, id); }
WidgetRef& WidgetRef::page(const char* id) {
  int p = ui_->pageIndexOf(id);
  if (p >= 0) { ui_->w_[idx_].pageIdx = (int8_t)p; strp(PKey::page, id); }
  return *this;
}
WidgetRef& WidgetRef::size(float w, int h) {
  if (h > 0) { char b[32]; char f[16]; fmtFloat(w, f, sizeof f); snprintf(b, sizeof b, "[%s,%d]", f, h); ui_->w_[idx_].setProp(PKey::size, Value::ofRaw(b)); }
  else nump(PKey::size, w);
  return *this;
}
WidgetRef& WidgetRef::disabled(bool on) { ui_->w_[idx_].set(Widget::Dis, on); return *this; }
WidgetRef& WidgetRef::readOnly(bool on) { ui_->w_[idx_].set(Widget::Ro, on); return *this; }
WidgetRef& WidgetRef::zone(float from, float to, const char* color) {
  Str item; StrSink sink(item);
  { JsonWriter jw(sink); jw.beginObj(); jw.kv("from", from); jw.kv("to", to); jw.kv("color", color); jw.endObj(); }
  appendToRawArray(ui_->w_[idx_], PKey::zones, item); return *this;
}
WidgetRef& WidgetRef::series(const char* id, const char* lbl, const char* color) {
  Str item; StrSink sink(item);
  { JsonWriter jw(sink); jw.beginObj(); jw.kv("id", id); if (lbl) jw.kv("lbl", lbl); if (color) jw.kv("color", color); jw.endObj(); }
  appendToRawArray(ui_->w_[idx_], PKey::series, item); return *this;
}
WidgetRef& WidgetRef::persist() {
  Widget& w = ui_->w_[idx_];
  if (!w.has(Widget::HasValue) || w.has(Widget::Output)) return *this;
  w.set(Widget::Persist, true);
  Value v;
  if (ui_->store_) {
    char key[16]; ui_->persistKey(w, key);
    if (ui_->store_->getValue(key, v) && ui_->validate(w, v)) { w.val = v; w.set(Widget::Restored, true); }
  }
  return *this;
}
WidgetRef& WidgetRef::value(const Value& v) { Value c = v; if (ui_->validate(ui_->w_[idx_], c)) ui_->w_[idx_].val = c; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(bool)> fn, bool*) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn(v.asBool()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(int)> fn, int*) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn((int)v.asInt()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(float)> fn, float*) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn(v.asFloat()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(double)> fn, double*) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn((double)v.asFloat()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(const Str&)> fn, Str*) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn(v.asStr()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(const char*)> fn, const char**) { ui_->handler(idx_).onChange = [fn](const Value& v) { fn(v.asStr().c_str()); }; return *this; }
WidgetRef& WidgetRef::onChangeImpl(std::function<void(const Value&)> fn, Value*) { ui_->handler(idx_).onChange = fn; return *this; }
WidgetRef& WidgetRef::onClick(std::function<void()> fn) { ui_->handler(idx_).onEvent = [fn](int v) { if (v) fn(); }; return *this; }
WidgetRef& WidgetRef::onEvent(EventFn fn) { ui_->handler(idx_).onEvent = fn; return *this; }
WidgetRef& WidgetRef::bind(bool& v) { ui_->w_[idx_].val = Value::ofBool(v); ui_->binds_.push_back({Binding::B, idx_, &v, ui_->w_[idx_].val}); return *this; }
WidgetRef& WidgetRef::bind(int& v) { Value c = Value::ofInt(v); ui_->validate(ui_->w_[idx_], c); ui_->w_[idx_].val = c; ui_->binds_.push_back({Binding::I, idx_, &v, c}); return *this; }
WidgetRef& WidgetRef::bind(float& v) { Value c = Value::ofFloat(v); ui_->validate(ui_->w_[idx_], c); ui_->w_[idx_].val = c; ui_->binds_.push_back({Binding::F, idx_, &v, c}); return *this; }
WidgetRef& WidgetRef::bind(Str& v) { ui_->w_[idx_].val = Value::ofStr(v); ui_->binds_.push_back({Binding::S, idx_, &v, ui_->w_[idx_].val}); return *this; }

// ---- PropRef ----------------------------------------------------------------
PropRef::PropRef(Ui* ui, const char* id) : ui_(ui), idx_(ui->find(id)) {}
PropRef& PropRef::str(PKey k, const char* v) { changes_.push_back({k, Value::ofStr(v)}); return *this; }
PropRef& PropRef::num(PKey k, float v) { changes_.push_back({k, Value::ofFloat(v)}); return *this; }
PropRef& PropRef::boolean(PKey k, bool v) { changes_.push_back({k, Value::ofBool(v)}); return *this; }
PropRef& PropRef::disabled(bool v) { return boolean(PKey::dis, v); }
PropRef& PropRef::visible(bool v) { vis_ = v; visSet_ = true; return *this; }
PropRef& PropRef::options(const std::vector<const char*>& opts) {
  changes_.push_back({PKey::opts, Value::ofRaw(jsonStrArray(opts))});
  if (idx_ >= 0) ui_->w_[idx_].nopts = (uint8_t)opts.size();
  return *this;
}
PropRef::~PropRef() {
  if (idx_ < 0 || (changes_.empty() && !visSet_)) return;
  Widget& w = ui_->w_[idx_];
  for (auto& c : changes_) {
    if (c.k == PKey::dis) w.set(Widget::Dis, c.v.asBool());
    else w.setProp(c.k, c.v);
  }
  if (visSet_) w.set(Widget::Hidden, !vis_);
  if (!ui_->host_) return;
  Str id = w.id; auto changes = changes_; bool visSet = visSet_, vis = vis_;
  ui_->host_->uiBroadcast(*ui_, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "prop"); jw.kv("id", id); jw.key("p"); jw.beginObj();
    for (auto& c : changes) jw.kv(pkeyName(c.k), c.v);
    if (visSet) jw.kv("vis", vis);
    jw.endObj(); jw.endObj();
  });
}

// ---- runtime ----------------------------------------------------------------
int Ui::find(const char* id) const {
  if (!id) return -1;
  for (size_t i = 0; i < w_.size(); i++) if (strEq(w_[i].id, id)) return (int)i;
  return -1;
}

int Ui::pageIndexOf(const char* id) const {
  for (size_t i = 0; i < pages_.size(); i++) if (strEq(w_[pages_[i]].id, id)) return (int)i;
  return -1;
}

Handler& Ui::handler(uint16_t idx) {
  for (auto& h : handlers_) if (h.idx == idx) return h;
  handlers_.push_back({idx, nullptr, nullptr});
  return handlers_.back();
}

void Ui::persistKey(const Widget& w, char out[16]) const { snprintf(out, 16, "%s", w.id.c_str()); }

bool Ui::validate(const Widget& w, Value& v) const {
  auto isInt = [](const Value& x) { return x.type == Value::Int || (x.type == Value::Float && x.f == floorf(x.f)); };
  auto num = [&](float& out) { if (!v.isNum()) return false; out = v.asFloat(); return true; };
  float f;
  switch (valueKind(w.ty)) {
    case VKind::Bool: return v.type == Value::Bool;
    case VKind::Num: {
      if (!num(f)) return false;
      float mn = w.numProp(PKey::min, 0), mx = w.numProp(PKey::max, 100);
      if (f < mn || f > mx) return false;
      v = Value::ofFloat(f); return true;
    }
    case VKind::Int: {
      if (!isInt(v)) return false;
      int32_t i = v.asInt();
      if (i < 0) return false;
      if (w.ty == WType::Select && i >= (int32_t)w.nopts) return false;
      if (w.ty == WType::Flags && w.nopts < 32 && i >= (1L << w.nopts)) return false;
      if (w.ty == WType::Color && i > 0xFFFFFF) return false;
      v = Value::ofInt(i); return true;
    }
    case VKind::Str: {
      if (v.type != Value::String) return false;
      int32_t maxlen = (int32_t)w.numProp(PKey::maxlen, w.ty == WType::Textarea ? 256 : 64);
      return (int32_t)v.s.length() <= maxlen;
    }
    case VKind::Pair: return v.type == Value::Pair && v.x >= -100 && v.x <= 100 && v.y >= -100 && v.y <= 100;
    case VKind::BoolOrInt: if (v.type == Value::Bool) return true; if (isInt(v)) { v = Value::ofInt(v.asInt()); return true; } return false;
    case VKind::NumOrStr: if (v.type == Value::String) return true; if (num(f)) { v = Value::ofFloat(f); return true; } return false;
    case VKind::Rows: return v.type == Value::Raw;
    default: return false;
  }
}

void Ui::fire(uint16_t idx, const Value& v) {
  for (auto& b : binds_) if (b.idx == idx) {
    switch (b.kind) {
      case Binding::B: *(bool*)b.ptr = v.asBool(); break;
      case Binding::I: *(int*)b.ptr = (int)v.asInt(); break;
      case Binding::F: *(float*)b.ptr = v.asFloat(); break;
      case Binding::S: *(Str*)b.ptr = v.asStr(); break;
    }
    b.last = v;
  }
  for (auto& h : handlers_) if (h.idx == idx && h.onChange) h.onChange(v);
}

bool Ui::set(const char* id, const Value& v) {
  int i = find(id);
  if (i < 0) return false;
  Widget& w = w_[i];
  if (!w.has(Widget::HasValue)) return false;
  Value c = v;
  if (!validate(w, c)) return false;
  if (c.equals(w.val)) return true;
  w.val = c; w.dirty = 0xFF;
  for (auto& b : binds_) if (b.idx == i) { b.last = c; switch (b.kind) {
    case Binding::B: *(bool*)b.ptr = c.asBool(); break; case Binding::I: *(int*)b.ptr = (int)c.asInt(); break;
    case Binding::F: *(float*)b.ptr = c.asFloat(); break; case Binding::S: *(Str*)b.ptr = c.asStr(); break; } }
  if (w.has(Widget::Persist) && store_) { char key[16]; persistKey(w, key); store_->putValue(key, c); }
  if (host_) host_->uiValueChanged(*this, (uint16_t)i);
  return true;
}

const Value* Ui::get(const char* id) const { int i = find(id); return i < 0 ? nullptr : &w_[i].val; }

bool Ui::applySet(uint16_t idx, Value v, uint8_t fromSlotBit, int& errCode) {
  Widget& w = w_[idx];
  if (!w.has(Widget::HasValue) || w.has(Widget::Ro) || w.has(Widget::Output) || w.has(Widget::Dis) || !validate(w, v)) {
    errCode = 7; w.dirty |= fromSlotBit; return false;
  }
  bool changed = !v.equals(w.val);
  w.val = v; w.dirty = 0xFF;
  if (changed && w.has(Widget::Persist) && store_) { char key[16]; persistKey(w, key); store_->putValue(key, v); }
  fire(idx, v);
  return true;
}

bool Ui::applyEvent(uint16_t idx, int v) {
  Widget& w = w_[idx];
  if (w.ty != WType::Button && w.ty != WType::Dpad) return false;
  if (w.has(Widget::Dis)) return false;
  for (auto& h : handlers_) if (h.idx == idx && h.onEvent) h.onEvent(v);
  return true;
}

void Ui::markAllDirty(uint8_t slotBit) { for (auto& w : w_) if (w.has(Widget::HasValue)) w.dirty |= slotBit; }

bool Ui::anyDirty(uint8_t slotBit, int8_t page) const {
  for (auto& w : w_) if ((w.dirty & slotBit) && visibleOnPage(w, page)) return true;
  return false;
}

void Ui::writeUi(JsonWriter& jw) const {
  jw.beginObj(); jw.kv("t", "ui"); jw.kv("rev", rev_); jw.key("w"); jw.beginArr();
  for (auto& w : w_) {
    jw.beginObj(); jw.kv("id", w.id); jw.kv("ty", wtypeName(w.ty));
    for (auto& p : w.props) jw.kv(pkeyName(p.k), p.v);
    if (w.has(Widget::Ro)) jw.kv("ro", true);
    if (w.has(Widget::Dis)) jw.kv("dis", true);
    if (w.has(Widget::Hidden)) jw.kv("vis", false);
    jw.endObj();
  }
  jw.endArr(); jw.endObj();
}

void Ui::writeUpd(JsonWriter& jw, uint8_t slotBit, int8_t page, bool all) {
  jw.beginObj(); jw.kv("t", "upd"); jw.key("v"); jw.beginObj();
  for (auto& w : w_) {
    if (!w.has(Widget::HasValue) || !visibleOnPage(w, page)) continue;
    if (!all && !(w.dirty & slotBit)) continue;
    jw.kv(w.id.c_str(), w.val);
    w.dirty &= ~slotBit;
  }
  jw.endObj(); jw.endObj();
}

void Ui::rebuild() { rev_++; if (host_) host_->uiRebuilt(*this); }

void Ui::dialogSend(const char* id, const char* kind, const char* msg, const char* def, const char* title, uint16_t timeoutS) {
  if (!host_) return;
  host_->uiBroadcast(*this, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "dlg"); jw.kv("id", id); jw.kv("kind", kind); jw.kv("msg", msg);
    if (title) jw.kv("title", title);
    if (def) jw.kv("def", def);
    jw.kv("timeout", (int32_t)timeoutS); jw.endObj();
  });
}

void Ui::confirm(const char* id, const char* msg, DialogFn cb, const char* title, uint16_t timeoutS) {
  answerDialog(id, false, "");
  dialogs_.push_back({Str(id), cb, (uint32_t)(nowMs() + (uint32_t)timeoutS * 1000u), true});
  dialogSend(id, "confirm", msg, nullptr, title, timeoutS);
}

void Ui::prompt(const char* id, const char* msg, DialogFn cb, const char* def, const char* title, uint16_t timeoutS) {
  answerDialog(id, false, "");
  dialogs_.push_back({Str(id), cb, (uint32_t)(nowMs() + (uint32_t)timeoutS * 1000u), true});
  dialogSend(id, "prompt", msg, def, title, timeoutS);
}

bool Ui::answerDialog(const char* id, bool ok, const char* text) {
  for (size_t i = 0; i < dialogs_.size(); i++) {
    if (!strEq(dialogs_[i].id, id)) continue;
    Dialog d = dialogs_[i];
    dialogs_.erase(dialogs_.begin() + i);
    if (host_) host_->uiBroadcast(*this, [&](JsonWriter& jw) { jw.beginObj(); jw.kv("t", "dlg"); jw.kv("id", id); jw.kv("close", true); jw.endObj(); });
    if (d.cb) d.cb(ok, Str(text ? text : ""));
    return true;
  }
  return false;
}

void Ui::push(const char* chartId, const char* seriesId, float v, uint64_t tsMs) {
  if (!host_) return;
  if (!tsMs) tsMs = nowMs();
  host_->uiBroadcast(*this, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "pts"); jw.kv("id", chartId); jw.kv("s", seriesId); jw.key("p"); jw.beginArr(); jw.beginArr();
    char b[24]; snprintf(b, sizeof b, "%llu", (unsigned long long)tsMs); jw.raw(b); jw.num(v); jw.endArr(); jw.endArr(); jw.endObj();
  });
}

void Ui::logLine(const char* logId, const char* msg, const char* color) {
  uint32_t ts = nowMs();
#if ESPFACE_LOG_HISTORY > 0
  int idx = find(logId);
  if (idx >= 0) {
    LogHist* h = nullptr;
    for (auto& l : logs_) if (l.idx == idx) h = &l;
    if (!h) { logs_.push_back({(uint16_t)idx, {}}); h = &logs_.back(); }
    Str line; StrSink sink(line);
    { JsonWriter jw(sink); jw.beginObj(); jw.kv("t", "log"); jw.kv("id", logId); jw.kv("msg", msg); if (color) jw.kv("c", color); jw.kv("ts", ts); jw.endObj(); }
    h->lines.push_back(line);
    while (h->lines.size() > ESPFACE_LOG_HISTORY) h->lines.erase(h->lines.begin());
  }
#endif
  if (!host_) return;
  host_->uiBroadcast(*this, [&](JsonWriter& jw) {
    jw.beginObj(); jw.kv("t", "log"); if (logId) jw.kv("id", logId); jw.kv("msg", msg); if (color) jw.kv("c", color); jw.kv("ts", ts); jw.endObj();
  });
}

size_t Ui::logHistory(uint16_t idx, const std::function<void(const Str&)>& fn) const {
  for (auto& l : logs_) if (l.idx == idx) { for (auto& s : l.lines) fn(s); return l.lines.size(); }
  return 0;
}

void Ui::loop(uint32_t now) {
  // restored persisted values fire their handlers once, after setup
  for (size_t i = 0; i < w_.size(); i++) if (w_[i].has(Widget::Restored)) { w_[i].set(Widget::Restored, false); fire((uint16_t)i, w_[i].val); }
  // bound variables changed by the sketch
  for (auto& b : binds_) {
    Value cur;
    switch (b.kind) {
      case Binding::B: cur = Value::ofBool(*(bool*)b.ptr); break;
      case Binding::I: cur = Value::ofInt(*(int*)b.ptr); break;
      case Binding::F: cur = Value::ofFloat(*(float*)b.ptr); break;
      case Binding::S: cur = Value::ofStr(*(Str*)b.ptr); break;
    }
    if (!cur.equals(b.last)) { b.last = cur; set(w_[b.idx].id.c_str(), cur); }
  }
  // dialog timeouts
  for (size_t i = 0; i < dialogs_.size();) {
    if ((int32_t)(now - dialogs_[i].deadline) >= 0) { Str id = dialogs_[i].id; answerDialog(id.c_str(), false, ""); }
    else i++;
  }
}

}  // namespace espface
