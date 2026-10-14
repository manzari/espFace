#pragma once
#include <functional>
#include <vector>
#include "Widget.h"
#include "../proto/Writer.h"
#include "../sys/Store.h"

namespace espface {

class Ui;
class JsonWriter;

// Implemented by Core: lets a Ui push messages to its clients.
class UiHost {
 public:
  virtual ~UiHost() {}
  virtual void uiBroadcast(Ui& ui, const std::function<void(JsonWriter&)>& fill) = 0;
  virtual void uiValueChanged(Ui& ui, uint16_t idx) = 0;
  virtual void uiRebuilt(Ui& ui) = 0;
};

// Deduce the first argument type of a callable (lambda, function pointer).
namespace detail {
template <class F> struct arg1 : arg1<decltype(&F::operator())> {};
template <class C, class R, class A> struct arg1<R (C::*)(A) const> { using type = A; };
template <class C, class R, class A> struct arg1<R (C::*)(A)> { using type = A; };
template <class R, class A> struct arg1<R (*)(A)> { using type = A; };
template <class T> struct strip { using type = typename std::remove_cv<typename std::remove_reference<T>::type>::type; };
}  // namespace detail

using ChangeFn = std::function<void(const Value&)>;
// button: 1 press, 0 release. dpad: char code 'u','d','l','r','c' on press, 0 on release.
using EventFn = std::function<void(int)>;
using MoveFn = std::function<void(int x, int y)>;   // joystick, each -100..100
using DialogFn = std::function<void(bool ok, const Str& text)>;

struct Handler {
  uint16_t idx;
  ChangeFn onChange;
  EventFn onEvent;
};

struct Binding {
  enum Kind : uint8_t { B, I, F, S } kind;
  uint16_t idx;
  void* ptr;
  Value last;
};

// Chainable reference returned by the builder.
class WidgetRef {
 public:
  WidgetRef(Ui* ui, uint16_t idx) : ui_(ui), idx_(idx) {}
  WidgetRef& group(const char* id);
  WidgetRef& page(const char* id);
  WidgetRef& row(const char* id);
  WidgetRef& size(float w, int h = 0);
  WidgetRef& square(bool on = true) { return flag(PKey::sq, on); }
  WidgetRef& disabled(bool on = true);
  WidgetRef& hint(const char* text) { return strp(PKey::hint, text); }
  WidgetRef& icon(const char* name) { return strp(PKey::icon, name); }
  WidgetRef& color(const char* hex) { return strp(PKey::color, hex); }
  WidgetRef& readOnly(bool on = true);
  WidgetRef& unit(const char* u) { return strp(PKey::unit, u); }
  WidgetRef& step(float s) { return nump(PKey::step, s); }
  WidgetRef& range(float min, float max) { nump(PKey::min, min); return nump(PKey::max, max); }
  WidgetRef& hold(bool on = true) { return flag(PKey::hold, on); }
  WidgetRef& spin(bool on = true) { return flag(PKey::spin, on); }
  WidgetRef& secret(bool on = true) { return flag(PKey::secret, on); }
  WidgetRef& regex(const char* re) { return strp(PKey::re, re); }
  WidgetRef& labels(const char* on, const char* off) { strp(PKey::on, on); return strp(PKey::off, off); }
  WidgetRef& style(const char* s) { return strp(PKey::style, s); }
  WidgetRef& fmt(const char* f) { return strp(PKey::fmt, f); }
  WidgetRef& fold(bool on = true) { return flag(PKey::fold, on); }
  WidgetRef& center(bool on = true) { return flag(PKey::center, on); }
  WidgetRef& legend(bool on) { return flag(PKey::legend, on); }
  WidgetRef& values(bool on) { return flag(PKey::vals, on); }
  WidgetRef& exp(bool on = true) { return flag(PKey::exp, on); }
  WidgetRef& rgb(bool on = true) { return flag(PKey::rgb, on); }
  WidgetRef& mode(const char* m) { return strp(PKey::mode, m); }
  WidgetRef& zone(float from, float to, const char* color);
  WidgetRef& series(const char* id, const char* lbl = nullptr, const char* color = nullptr);
  WidgetRef& column(const char* lbl, float w = 1, const char* align = "left");
  WidgetRef& maxlen(int n) { return nump(PKey::maxlen, (float)n); }
  WidgetRef& persist();
  WidgetRef& value(const Value& v);
  WidgetRef& value(bool v) { return value(Value::ofBool(v)); }
  WidgetRef& value(float v) { return value(Value::ofFloat(v)); }
  WidgetRef& value(int v) { return value(Value::ofInt(v)); }
  WidgetRef& value(const char* v) { return value(Value::ofStr(v)); }

  template <class F> WidgetRef& onChange(F fn) {
    using A = typename detail::strip<typename detail::arg1<F>::type>::type;
    return onChangeImpl(fn, (A*)nullptr);
  }
  WidgetRef& onClick(std::function<void()> fn);
  WidgetRef& onEvent(EventFn fn);
  WidgetRef& onMove(MoveFn fn);
  WidgetRef& bind(bool& v);
  WidgetRef& bind(int& v);
  WidgetRef& bind(float& v);
  WidgetRef& bind(Str& v);

  uint16_t index() const { return idx_; }

 private:
  friend class Ui;
  WidgetRef& flag(PKey k, bool on);
  WidgetRef& strp(PKey k, const char* v);
  WidgetRef& nump(PKey k, float v);
  WidgetRef& onChangeImpl(std::function<void(bool)> fn, bool*);
  WidgetRef& onChangeImpl(std::function<void(int)> fn, int*);
  WidgetRef& onChangeImpl(std::function<void(uint32_t)> fn, uint32_t*);
  WidgetRef& onChangeImpl(std::function<void(float)> fn, float*);
  WidgetRef& onChangeImpl(std::function<void(double)> fn, double*);
  WidgetRef& onChangeImpl(std::function<void(const Str&)> fn, Str*);
  WidgetRef& onChangeImpl(std::function<void(const char*)> fn, const char**);
  WidgetRef& onChangeImpl(std::function<void(const Value&)> fn, Value*);
  Ui* ui_;
  uint16_t idx_;
};

// Runtime prop updates: ui.prop("id").label("x").color("#f00") sends one prop message on destruction.
class PropRef {
 public:
  PropRef(Ui* ui, const char* id);
  ~PropRef();
  PropRef& label(const char* v) { return str(PKey::lbl, v); }
  PropRef& color(const char* v) { return str(PKey::color, v); }
  PropRef& hint(const char* v) { return str(PKey::hint, v); }
  PropRef& icon(const char* v) { return str(PKey::icon, v); }
  PropRef& unit(const char* v) { return str(PKey::unit, v); }
  PropRef& src(const char* v) { return str(PKey::src, v); }
  PropRef& text(const char* v) { return str(PKey::text, v); }
  PropRef& min(float v) { return num(PKey::min, v); }
  PropRef& max(float v) { return num(PKey::max, v); }
  PropRef& step(float v) { return num(PKey::step, v); }
  PropRef& disabled(bool v);
  PropRef& visible(bool v);
  PropRef& options(const std::vector<const char*>& opts);
  PropRef& str(PKey k, const char* v);
  PropRef& num(PKey k, float v);
  PropRef& boolean(PKey k, bool v);
 private:
  Ui* ui_;
  int idx_;
  std::vector<Prop> changes_;
  bool vis_ = false, visSet_ = false;
};

class Ui {
 public:
  explicit Ui(const char* name = "main") : name_(name) {}
  ~Ui() { delete store_; }
  Ui(const Ui&) = delete;
  Ui& operator=(const Ui&) = delete;
  void attach(UiHost* host, Store* store) { host_ = host; base_ = store; delete store_; store_ = nullptr; }
  const char* name() const { return name_; }
  // NVS namespace of persisted values: "efv_<name>", or "efv_<fnv1a hex>" for names over 11 characters
  static void persistNs(const char* name, char out[16]);

  // per-UI PIN override: nullptr = use the global PIN, "" = no PIN for this UI
  Ui& pin(const char* p) { pinSet_ = true; pin_ = p ? p : ""; return *this; }
  bool hasPinOverride() const { return pinSet_; }
  const char* pinOverride() const { return pin_.c_str(); }

  // ---- builder --------------------------------------------------------
  WidgetRef page(const char* id, const char* lbl);
  WidgetRef header(const char* lbl);
  WidgetRef group(const char* id, const char* lbl);
  WidgetRef row(const char* id);
  WidgetRef spacer(const char* id, float w = 1, int h = 8);
  WidgetRef label(const char* id, const char* lbl, const char* unit = nullptr);
  WidgetRef button(const char* id, const char* lbl);
  WidgetRef sw(const char* id, const char* lbl);
  WidgetRef slider(const char* id, const char* lbl, float min, float max, float step = 1, const char* unit = nullptr);
  WidgetRef number(const char* id, const char* lbl, float min, float max, float step = 1, const char* unit = nullptr);
  WidgetRef text(const char* id, const char* lbl, int maxlen = 64);
  WidgetRef select(const char* id, const char* lbl, const std::vector<const char*>& opts);
  WidgetRef gauge(const char* id, const char* lbl, float min, float max, const char* unit = nullptr);
  WidgetRef progress(const char* id, const char* lbl, float min = 0, float max = 100);
  WidgetRef led(const char* id, const char* lbl, const char* color = nullptr);
  WidgetRef chart(const char* id, const char* lbl, int winSeconds = 300, const char* unit = nullptr);
  WidgetRef textblock(const char* id, const char* text);
  WidgetRef log(const char* id, const char* lbl, int cap = 200, int rows = 8);
  WidgetRef textarea(const char* id, const char* lbl, int maxlen = 256, int rows = 4);
  WidgetRef flags(const char* id, const char* lbl, const std::vector<const char*>& opts);
  WidgetRef color(const char* id, const char* lbl);
  WidgetRef datetime(const char* id, const char* lbl, const char* mode = "datetime");
  WidgetRef joystick(const char* id, const char* lbl);
  WidgetRef dpad(const char* id, const char* lbl);
  WidgetRef display(const char* id, const char* lbl, int digits = 4, const char* unit = nullptr);
  WidgetRef table(const char* id, const char* lbl);     // add columns with .column(); needs at least one
  WidgetRef image(const char* id, const char* lbl, const char* src);
  WidgetRef stream(const char* id, const char* lbl, const char* src);
  WidgetRef clock(const char* id, const char* lbl, const char* fmt = nullptr);   // Core pushes the device time
  WidgetRef map(const char* id, const char* lbl, int zoom = 12);
  WidgetRef add(WType ty, const char* id, const char* lbl = nullptr);

  // ---- runtime ----------------------------------------------------------
  bool set(const char* id, const Value& v);            // from the sketch: updates value, pushes to clients
  bool set(const char* id, bool v) { return set(id, Value::ofBool(v)); }
  bool set(const char* id, float v) { return set(id, Value::ofFloat(v)); }
  bool set(const char* id, int v) { return set(id, Value::ofInt(v)); }
  bool set(const char* id, uint32_t v) { return set(id, Value::ofInt((int32_t)v)); }
  bool set(const char* id, const char* v) { return set(id, Value::ofStr(v)); }
  bool set(const char* id, int x, int y) { return set(id, Value::ofPair((int16_t)x, (int16_t)y)); }
  // table rows / map points as a raw JSON array, e.g. [["Kitchen",21.5],["Bath",23]] or [[52.52,13.4,"Home"]]
  bool setRows(const char* id, const char* rowsJson) { return set(id, Value::ofRaw(rowsJson)); }
  bool setPoints(const char* id, const char* pointsJson) { return setRows(id, pointsJson); }
  void tickClocks(uint32_t unix);
  const Value* get(const char* id) const;
  PropRef prop(const char* id) { return PropRef(this, id); }
  void show(const char* id, bool visible) { prop(id).visible(visible); }
  void rebuild();                                       // bump rev and resend ui to all clients
  void confirm(const char* id, const char* msg, DialogFn cb, const char* title = nullptr, uint16_t timeoutS = 60);
  void prompt(const char* id, const char* msg, DialogFn cb, const char* def = nullptr, const char* title = nullptr, uint16_t timeoutS = 60);
  void push(const char* chartId, const char* seriesId, float v, uint64_t tsMs = 0);
  void logLine(const char* logId, const char* msg, const char* color = nullptr);

  // ---- used by Core -----------------------------------------------------
  int find(const char* id) const;
  Widget& at(uint16_t i) { return w_[i]; }
  const Widget& at(uint16_t i) const { return w_[i]; }
  size_t count() const { return w_.size(); }
  uint32_t rev() const { return rev_; }
  int pageIndexOf(const char* id) const;                // index among pages, or -1
  int firstPageIdx() const { return pages_.empty() ? -1 : 0; }
  bool anyDirty(uint8_t slotBit, int8_t page) const;
  size_t logHistory(uint16_t idx, const std::function<void(const Str&)>& fn) const;
  int8_t pageSlotOf(const Widget& w) const { return w.pageIdx < 0 ? (int8_t)firstPageIdx() : w.pageIdx; }
  bool visibleOnPage(const Widget& w, int8_t page) const { return page < 0 || pageSlotOf(w) == page; }
  void writeUi(JsonWriter& jw) const;
  void writeUpd(JsonWriter& jw, uint8_t slotBit, int8_t page, bool all);
  bool applySet(uint16_t idx, Value v, uint8_t fromSlotBit, int& errCode);   // from client
  bool applyEvent(uint16_t idx, int v);
  bool answerDialog(const char* id, bool ok, const char* text);
  void loop(uint32_t now);
  void markAllDirty(uint8_t slotBit);
  struct Dialog { Str id, kind, msg, def, title; DialogFn cb; uint32_t deadline; };
  const std::vector<Dialog>& dialogs() const { return dialogs_; }     // open dialogs, re-sent to late joiners
  void writeDialog(JsonWriter& jw, const Dialog& d, uint32_t now) const;

 private:
  friend class WidgetRef;
  friend class PropRef;
  WidgetRef push_(WType ty, const char* id, const char* lbl);
  Handler& handler(uint16_t idx);
  void fire(uint16_t idx, const Value& v);
  bool validate(const Widget& w, Value& v) const;
  void persistKey(const Widget& w, char out[16]) const;
  Store* store();
  void dialogOpen(const char* id, const char* kind, const char* msg, const char* def, const char* title, DialogFn cb, uint16_t timeoutS);


  const char* name_;
  UiHost* host_ = nullptr;
  Store* base_ = nullptr;
  Store* store_ = nullptr;
  bool pinSet_ = false;
  Str pin_;
  uint32_t rev_ = 1;
  std::vector<Widget> w_;
  std::vector<uint16_t> pages_;
  std::vector<Handler> handlers_;
  std::vector<Binding> binds_;
  std::vector<Dialog> dialogs_;
  int8_t curPage_ = -1;   // page applied to widgets declared after ui.page()
  struct LogHist { uint16_t idx; std::vector<Str> lines; };
  std::vector<LogHist> logs_;
};

}  // namespace espface
