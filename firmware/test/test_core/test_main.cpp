// Native unit tests for the espFace core. Every device message is appended to test_output/d2c.jsonl
// so the protocol validator can schema-check them afterwards.
#include <unity.h>
#include <ArduinoJson.h>
#include <stdio.h>
#include <sys/stat.h>
#include <vector>
#include "core/Core.h"
#include "util/Hmac.h"

using namespace espface;

static FILE* g_out = nullptr;

struct MemTransport : public Transport {
  std::vector<Str> msgs[ESPFACE_MAX_CLIENTS];
  Str partial[ESPFACE_MAX_CLIENTS];
  std::vector<uint8_t> closed;
  const char* name() const override { return "mem"; }
  bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) override {
    if (first) partial[slot] = "";
    for (size_t i = 0; i < len; i++) partial[slot] += data[i];
    if (last) { msgs[slot].push_back(partial[slot]); if (g_out) fprintf(g_out, "%s\n", partial[slot].c_str()); }
    return true;
  }
  void close(uint8_t slot) override { closed.push_back(slot); }
  int count(uint8_t slot = 0) { return (int)msgs[slot].size(); }
  JsonDocument last(uint8_t slot = 0) { JsonDocument d; deserializeJson(d, msgs[slot].back()); return d; }
  JsonDocument at(uint8_t slot, int i) { JsonDocument d; deserializeJson(d, msgs[slot][i]); return d; }
  int find(const char* needle, uint8_t slot = 0, int from = 0) {
    for (int i = from; i < (int)msgs[slot].size(); i++) if (strstr(msgs[slot][i].c_str(), needle)) return i;
    return -1;
  }
  void clear() { for (auto& m : msgs) m.clear(); }
};

struct Rig {
  MemStore store;
  MemTransport tr;
  Core core;
  int slot = -1;
  Rig(const char* pin = nullptr) {
    core.setId("a1b2c3").setVersion("1.0.0");
    core.addTransport(&tr);
    core.begin("Test", &store);
    if (pin) core.setPin(pin, true);
  }
  void open() { slot = core.onOpen(&tr); }
  void sendMsg(const char* json) { core.onMessage((uint8_t)slot, json, strlen(json)); }
  void hello(const char* tok = nullptr) {
    Str m = "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"";
    if (tok) { m += ",\"tok\":\""; m += tok; m += "\""; }
    m += "}";
    sendMsg(m.c_str());
  }
  bool authWithPin(const char* pin) {
    JsonDocument h = tr.last((uint8_t)slot);
    const char* nonce = h["nonce"];
    if (!nonce) return false;
    char mac[65]; pinMac(pin, nonce, "a1b2c3", mac);
    Str m = "{\"t\":\"auth\",\"mac\":\""; m += mac; m += "\"}";
    sendMsg(m.c_str());
    JsonDocument a = tr.at((uint8_t)slot, tr.find("\"t\":\"auth\"", (uint8_t)slot, tr.count((uint8_t)slot) - 3));
    return a["ok"] | false;
  }
};

static void buildDemo(Ui& ui) {
  ui.page("main", "Main").icon("home");
  ui.header("Boiler");
  ui.group("sensors", "Sensors");
  ui.gauge("temp", "Temperature", 0, 120, "°C").style("round").zone(90, 120, "#ff0000").group("sensors");
  ui.chart("tchart", "History", 600, "°C").series("temp", "Temp", "#ff8800").group("sensors");
  ui.progress("level", "Tank").group("sensors");
  ui.led("ok", "OK", "#00ff00").group("sensors");
  ui.label("note", "Note").group("sensors");
  ui.group("control", "Control");
  ui.row("r1").group("control");
  ui.sw("pump", "Pump").labels("ON", "OFF").row("r1").size(1).group("control");
  ui.slider("target", "Target", 20, 90, 1, "°C").row("r1").size(3).group("control");
  ui.number("n", "Cycles", 0, 10).spin().group("control");
  ui.select("mode", "Mode", {"Off", "Auto", "Manual"}).style("seg").group("control");
  ui.button("reset", "Reset").hint("Clears").icon("restart_alt").group("control");
  ui.button("horn", "Horn").hold().color("#ff8800").group("control");
  ui.text("name", "Name", 32).regex("^[A-Za-z ]*$");
  ui.spacer("sp", 1, 16);
  ui.log("term", "Log", 100, 6);
  ui.textblock("help", "Line 1\n\"quoted\"");
  ui.page("setup", "Setup").icon("settings");
  ui.text("pw", "Password", 64).secret();
}

// Phase 1b widgets, mirrors the I/O part of tools/fake-device demo-ui.mjs.
static void buildIo(Ui& ui) {
  ui.page("main", "Main");
  ui.progress("bal", "Balance", -100, 100).center();
  ui.display("disp", "Pressure", 5, "bar");
  ui.led("rgb", "Status").rgb();
  ui.clock("now", "Device time", "HH:mm:ss");
  ui.page("io", "I/O").icon("tune");
  ui.group("inputs", "Inputs");
  ui.joystick("joy", "Valve").center().exp().square().group("inputs");
  ui.dpad("pad", "Move").group("inputs");
  ui.color("col", "Light").group("inputs");
  ui.datetime("start", "Start", "time").group("inputs");
  ui.flags("days", "Days", {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}).group("inputs");
  ui.table("tbl", "Zones").column("Zone", 2).column("°C", 1, "right");
  ui.image("img", "Diagram", "https://example.com/a.png");
  ui.stream("cam", "Camera", "http://192.168.1.60:81/stream");
  ui.map("pos", "Location", 14);
  ui.textarea("notes", "Notes", 512, 4);
}

static WidgetRef ref(Ui& ui, const char* id) { return WidgetRef(&ui, (uint16_t)ui.find(id)); }

// ---- tests -----------------------------------------------------------------------
void test_hmac_vector() {
  char mac[65];
  pinMac("1234", "00112233445566778899aabbccddeeff", "a1b2c3", mac);
  TEST_ASSERT_EQUAL_STRING("03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8", mac);
}

void test_json_writer_escapes() {
  Str out; StrSink s(out);
  { JsonWriter jw(s); jw.beginObj(); jw.kv("a", "x\"y\\z\n"); jw.key("b"); jw.beginArr(); jw.num(1.5f); jw.integer(-2); jw.boolean(true); jw.endArr(); jw.kv("c", 3.0f); jw.endObj(); }
  TEST_ASSERT_EQUAL_STRING("{\"a\":\"x\\\"y\\\\z\\n\",\"b\":[1.5,-2,true],\"c\":3}", out.c_str());
}

void test_hello_without_pin_sends_ui_and_upd() {
  Rig r; buildDemo(r.core.ui()); r.open(); r.hello();
  TEST_ASSERT_EQUAL(3, r.tr.count());
  JsonDocument h = r.tr.at(0, 0);
  TEST_ASSERT_EQUAL_STRING("hello", h["t"]);
  TEST_ASSERT_TRUE(h["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("none", h["auth"]);
  TEST_ASSERT_EQUAL_STRING("a1b2c3", h["id"]);
  JsonDocument ui = r.tr.at(0, 1);
  TEST_ASSERT_EQUAL_STRING("ui", ui["t"]);
  TEST_ASSERT_EQUAL(22, ui["w"].size());
  TEST_ASSERT_EQUAL_STRING("gauge", ui["w"][3]["ty"]);
  TEST_ASSERT_EQUAL_STRING("round", ui["w"][3]["style"]);
  TEST_ASSERT_EQUAL(90, ui["w"][3]["zones"][0]["from"].as<int>());
  TEST_ASSERT_EQUAL_STRING("main", ui["w"][3]["page"]);
  TEST_ASSERT_EQUAL_STRING("setup", ui["w"][21]["page"]);
  TEST_ASSERT_TRUE(ui["w"][21]["secret"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("Line 1\n\"quoted\"", ui["w"][19]["text"]);
  JsonDocument upd = r.tr.at(0, 2);
  TEST_ASSERT_EQUAL_STRING("upd", upd["t"]);
  TEST_ASSERT_EQUAL(20, upd["v"]["target"].as<int>());
  TEST_ASSERT_FALSE(upd["v"]["pw"].is<const char*>());  // setup page not sent on the main page
}

void test_pin_flow_wrong_then_right_then_token() {
  Rig r("1234"); buildDemo(r.core.ui()); r.open(); r.hello();
  JsonDocument h = r.tr.last();
  TEST_ASSERT_FALSE(h["ok"].as<bool>());
  TEST_ASSERT_EQUAL(32, strlen(h["nonce"] | ""));
  r.sendMsg("{\"t\":\"set\",\"id\":\"pump\",\"v\":true}");
  TEST_ASSERT_EQUAL(3, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"auth\",\"mac\":\"0000000000000000000000000000000000000000000000000000000000000000\"}");
  JsonDocument a = r.tr.last();
  TEST_ASSERT_FALSE(a["ok"].as<bool>());
  TEST_ASSERT_EQUAL(4, a["left"].as<int>());
  // the device issued a fresh nonce internally; fetch it through the client state
  Client* c = r.core.client((uint8_t)r.slot);
  TEST_ASSERT_TRUE(c->hasNonce);
  char mac[65]; pinMac("1234", c->nonce, "a1b2c3", mac);
  Str m = "{\"t\":\"auth\",\"mac\":\""; m += mac; m += "\"}";
  r.sendMsg(m.c_str());
  int ai = r.tr.find("\"tok\"");
  TEST_ASSERT_TRUE(ai >= 0);
  JsonDocument ok = r.tr.at(0, ai);
  TEST_ASSERT_TRUE(ok["ok"].as<bool>());
  Str tok = ok["tok"].as<const char*>();
  TEST_ASSERT_EQUAL(32, tok.length());
  TEST_ASSERT_EQUAL_STRING("ui", r.tr.at(0, ai + 1)["t"]);
  // token reconnect on a second slot
  int s2 = r.core.onOpen(&r.tr);
  Str hm = "{\"t\":\"hello\",\"v\":1,\"client\":\"web\",\"tok\":\""; hm += tok; hm += "\"}";
  r.core.onMessage((uint8_t)s2, hm.c_str(), hm.length());
  TEST_ASSERT_TRUE(r.tr.at((uint8_t)s2, 0)["ok"].as<bool>());
  TEST_ASSERT_EQUAL(2, r.core.clients());
  // revoke drops the other session and invalidates the token
  { const char* m = "{\"t\":\"sys\",\"cmd\":\"revoke\"}"; r.core.onMessage((uint8_t)s2, m, strlen(m)); }
  TEST_ASSERT_EQUAL(1, r.tr.closed.size());
  TEST_ASSERT_FALSE(r.core.auth().validToken(tok.c_str()));
}

void test_lockout_after_five_failures() {
  Rig r("1234"); r.open(); r.hello();
  for (int i = 0; i < 5; i++) r.sendMsg("{\"t\":\"auth\",\"mac\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"}");
  JsonDocument a = r.tr.last();
  TEST_ASSERT_EQUAL(60, a["lock"].as<int>());
  int s2 = r.core.onOpen(&r.tr);
  r.core.onMessage((uint8_t)s2, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  JsonDocument h = r.tr.last((uint8_t)s2);
  TEST_ASSERT_FALSE(h["ok"].as<bool>());
  TEST_ASSERT_TRUE(h["lock"].as<int>() > 0);
  TEST_ASSERT_FALSE(h["nonce"].is<const char*>());
}

void test_set_validation_callbacks_and_bind() {
  Rig r; buildDemo(r.core.ui());
  float target = 0; bool pumpVar = false; int changes = 0;
  r.core.ui().slider("t2", "T2", 0, 10).page("main").bind(target);
  r.core.ui().sw("p2", "P2").page("main").bind(pumpVar);
  r.core.ui().slider("t3", "T3", 0, 10).page("main").onChange([&](float v) { changes++; TEST_ASSERT_EQUAL_FLOAT(7.0f, v); });
  r.open(); r.hello(); r.tr.clear();
  r.sendMsg("{\"t\":\"set\",\"id\":\"target\",\"v\":500}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"set\",\"id\":\"temp\",\"v\":5}");           // output widget
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"set\",\"id\":\"mode\",\"v\":3}");           // index out of range
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"set\",\"id\":\"nope\",\"v\":1}");
  TEST_ASSERT_EQUAL(6, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"set\",\"id\":\"t3\",\"v\":7}");
  r.sendMsg("{\"t\":\"set\",\"id\":\"t2\",\"v\":4.5}");
  r.sendMsg("{\"t\":\"set\",\"id\":\"p2\",\"v\":true}");
  TEST_ASSERT_EQUAL(1, changes);
  TEST_ASSERT_EQUAL_FLOAT(4.5f, target);
  TEST_ASSERT_TRUE(pumpVar);
  // echo arrives on the next flush, coalesced into one upd (also the rejected target is re-sent)
  int before = r.tr.count();
  r.core.loop();
  TEST_ASSERT_EQUAL(before, r.tr.count());  // not yet: flush interval
  Client* c = r.core.client((uint8_t)r.slot); c->lastFlush -= 1000;
  r.core.loop();
  JsonDocument upd = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("upd", upd["t"]);
  TEST_ASSERT_EQUAL_FLOAT(4.5f, upd["v"]["t2"].as<float>());
  TEST_ASSERT_EQUAL(7, upd["v"]["t3"].as<int>());
  TEST_ASSERT_TRUE(upd["v"]["p2"].as<bool>());
  TEST_ASSERT_EQUAL(20, upd["v"]["target"].as<int>());
  // sketch changes a bound variable -> pushed on next flush
  target = 9; c->lastFlush -= 1000; r.core.loop();
  TEST_ASSERT_EQUAL(9, r.tr.last()["v"]["t2"].as<int>());
  // face.set on an output widget
  r.core.ui().set("temp", 42.5f); c->lastFlush -= 1000; r.core.loop();
  TEST_ASSERT_EQUAL_FLOAT(42.5f, r.tr.last()["v"]["temp"].as<float>());
}

void test_events_hold_and_click() {
  Rig r; int clicks = 0, last = -1;
  r.core.ui().button("b", "B").onClick([&] { clicks++; });
  r.core.ui().button("h", "H").hold().onEvent([&](int v) { last = v; });
  r.open(); r.hello();
  r.sendMsg("{\"t\":\"ev\",\"id\":\"b\"}");
  r.sendMsg("{\"t\":\"ev\",\"id\":\"h\",\"v\":1}");
  TEST_ASSERT_EQUAL(1, last);
  r.sendMsg("{\"t\":\"ev\",\"id\":\"h\",\"v\":0}");
  TEST_ASSERT_EQUAL(1, clicks);
  TEST_ASSERT_EQUAL(0, last);
}

void test_persist_restores_value() {
  MemStore store;
  {
    Rig r; r.core.ui().slider("target", "T", 0, 100).persist();
    // move the store: Rig has its own, so reuse via a second core below sharing `store`
  }
  MemTransport tr; Core a; a.setId("a1b2c3"); a.addTransport(&tr); a.begin("A", &store);
  int fired = 0; float seen = 0;
  a.ui().slider("target", "T", 0, 100).persist().onChange([&](float v) { fired++; seen = v; });
  int s = a.onOpen(&tr); a.onMessage((uint8_t)s, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  a.onMessage((uint8_t)s, "{\"t\":\"set\",\"id\":\"target\",\"v\":66}", 34);
  Str raw; TEST_ASSERT_TRUE(store.getStr("target", raw));
  TEST_ASSERT_EQUAL_STRING("f66", raw.c_str());
  TEST_ASSERT_EQUAL(1, fired);
  Core b; b.setId("a1b2c3"); b.begin("B", &store);
  int fired2 = 0; float seen2 = 0;
  b.ui().slider("target", "T", 0, 100).persist().onChange([&](float v) { fired2++; seen2 = v; });
  TEST_ASSERT_EQUAL_FLOAT(66.f, b.ui().get("target")->asFloat());
  TEST_ASSERT_EQUAL(0, fired2);
  b.loop();
  TEST_ASSERT_EQUAL(1, fired2);
  TEST_ASSERT_EQUAL_FLOAT(66.f, seen2);
}

void test_page_filter() {
  Rig r; buildDemo(r.core.ui()); r.open(); r.hello(); r.tr.clear();
  r.sendMsg("{\"t\":\"page\",\"id\":\"setup\"}");
  JsonDocument upd = r.tr.last();
  TEST_ASSERT_TRUE(upd["v"]["pw"].is<const char*>());
  TEST_ASSERT_FALSE(upd["v"]["target"].is<int>());
  r.sendMsg("{\"t\":\"page\",\"id\":\"zzz\"}");
  TEST_ASSERT_EQUAL(6, r.tr.last()["code"].as<int>());
  // values changed on a hidden page are not pushed, but sent when the page becomes visible
  r.core.ui().set("target", 55.f);
  Client* c = r.core.client((uint8_t)r.slot); c->lastFlush -= 1000; r.tr.clear(); r.core.loop();
  TEST_ASSERT_EQUAL(0, r.tr.count());
  r.sendMsg("{\"t\":\"page\",\"id\":\"main\"}");
  TEST_ASSERT_EQUAL(55, r.tr.last()["v"]["target"].as<int>());
}

void test_dialogs_props_toast_log_chart() {
  Rig r; buildDemo(r.core.ui()); r.open(); r.hello(); r.tr.clear();
  bool answered = false; Str text;
  r.core.ui().prompt("d1", "Name?", [&](bool ok, const Str& v) { answered = ok; text = v; }, "Boiler", "Rename");
  JsonDocument d = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("prompt", d["kind"]);
  TEST_ASSERT_EQUAL_STRING("Boiler", d["def"]);
  r.sendMsg("{\"t\":\"dlg\",\"id\":\"d1\",\"ok\":true,\"v\":\"Kitchen\"}");
  TEST_ASSERT_TRUE(answered);
  TEST_ASSERT_EQUAL_STRING("Kitchen", text.c_str());
  TEST_ASSERT_TRUE(r.tr.last()["close"].as<bool>());
  r.sendMsg("{\"t\":\"dlg\",\"id\":\"d1\",\"ok\":true}");
  TEST_ASSERT_EQUAL(6, r.tr.last()["code"].as<int>());
  // timeout
  bool timedOut = false;
  r.core.ui().confirm("d2", "Sure?", [&](bool ok, const Str&) { timedOut = !ok; }, nullptr, 1);
  r.core.loop(); TEST_ASSERT_FALSE(timedOut);
  // props
  r.core.ui().prop("temp").label("Hot").color("#ff0000").max(150);
  JsonDocument p = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("prop", p["t"]);
  TEST_ASSERT_EQUAL_STRING("Hot", p["p"]["lbl"]);
  TEST_ASSERT_EQUAL(150, p["p"]["max"].as<int>());
  r.core.ui().show("reset", false);
  TEST_ASSERT_FALSE(r.tr.last()["p"]["vis"].as<bool>());
  r.core.ui().prop("mode").options({"A", "B"}).disabled(true);
  TEST_ASSERT_EQUAL(2, r.tr.last()["p"]["opts"].size());
  r.sendMsg("{\"t\":\"set\",\"id\":\"mode\",\"v\":1}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());  // disabled now
  // rebuild resends ui with the new props and a higher rev
  r.core.ui().rebuild();
  int ui = r.tr.find("\"rev\":2");
  TEST_ASSERT_TRUE(ui >= 0);
  TEST_ASSERT_TRUE(r.tr.at(0, ui)["w"][3]["lbl"] == "Hot");
  TEST_ASSERT_TRUE(r.tr.at(0, ui)["w"][14]["vis"] == false);
  // toast, log, chart
  r.core.toast("warn", "Hot!");
  TEST_ASSERT_EQUAL_STRING("warn", r.tr.last()["lvl"]);
  r.core.ui().logLine("term", "line", "#ff0000");
  TEST_ASSERT_EQUAL_STRING("term", r.tr.last()["id"]);
  r.core.ui().push("tchart", "temp", 21.5f, 1234);
  JsonDocument pts = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("pts", pts["t"]);
  TEST_ASSERT_EQUAL(1234, pts["p"][0][0].as<int>());
  TEST_ASSERT_EQUAL_FLOAT(21.5f, pts["p"][0][1].as<float>());
}

void test_sys_info_time_reboot_and_errors() {
  Rig r; r.open(); r.hello(); r.tr.clear();
  r.sendMsg("{\"t\":\"time\",\"unix\":1728700000,\"tz\":120}");
  TEST_ASSERT_EQUAL(1728700000u, r.core.time());
  TEST_ASSERT_EQUAL(120, r.core.tz());
  r.core.infoFill = [](JsonWriter& jw) { jw.kv("chip", "ESP32-S3"); jw.kv("heap", (uint32_t)12345); jw.kv("rr", "power"); };
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"info\"}");
  JsonDocument i = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("info", i["cmd"]);
  TEST_ASSERT_EQUAL_STRING("ESP32-S3", i["chip"]);
  TEST_ASSERT_EQUAL_STRING("1.0.0", i["fw"]);
  TEST_ASSERT_EQUAL(1728700000u, i["time"].as<uint32_t>());
  TEST_ASSERT_EQUAL(1, i["clients"].as<int>());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"wifi.scan\"}");
  TEST_ASSERT_EQUAL(8, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"bogus\"}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{not json");
  TEST_ASSERT_EQUAL(1, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"unknown_type\"}");
  TEST_ASSERT_EQUAL(1, r.tr.last()["code"].as<int>());  // still the previous err: unknown types are ignored
  bool rebooted = false; RebootReason why = RebootReason::Sketch;
  r.core.onReboot([&](RebootReason rr) { why = rr; });
  r.core.rebootFn = [&] { rebooted = true; };
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"reboot\"}");
  TEST_ASSERT_TRUE(r.tr.last()["ok"].as<bool>());
  r.core.requestReboot(RebootReason::Sketch, 0);   // ignored, one pending
  r.core.loop(); TEST_ASSERT_FALSE(rebooted);
  // sys pin.set turns auth on and clears tokens
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"pin.set\",\"pin\":\"9999\"}");
  TEST_ASSERT_TRUE(r.tr.last()["ok"].as<bool>());
  TEST_ASSERT_TRUE(r.core.auth().hasPin());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"pin.set\",\"pin\":\"12\"}");
  TEST_ASSERT_FALSE(r.tr.last()["ok"].as<bool>());
}

void test_multiple_uis_per_transport_and_pin_override() {
  Rig r("1234");
  r.core.ui().label("a", "A");
  Ui& setup = r.core.addUi("setup");
  setup.pin("");                      // open UI
  setup.text("ssid", "SSID");
  MemTransport tr2; r.core.addTransport(&tr2); tr2.use(setup);
  int s = r.core.onOpen(&tr2);
  r.core.onMessage((uint8_t)s, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  TEST_ASSERT_TRUE(tr2.at((uint8_t)s, 0)["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("none", tr2.at((uint8_t)s, 0)["auth"]);
  TEST_ASSERT_EQUAL_STRING("ssid", tr2.at((uint8_t)s, 1)["w"][0]["id"]);
  r.open(); r.hello();
  TEST_ASSERT_FALSE(r.tr.last((uint8_t)r.slot)["ok"].as<bool>());  // main UI still needs the PIN
}

void test_max_clients() {
  Rig r; r.core.ui().label("a", "A");
  for (int i = 0; i < ESPFACE_MAX_CLIENTS; i++) { int s = r.core.onOpen(&r.tr); r.core.onMessage((uint8_t)s, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36); }
  TEST_ASSERT_EQUAL(-1, r.core.onOpen(&r.tr));
  r.core.onClose(0);
  TEST_ASSERT_EQUAL(ESPFACE_MAX_CLIENTS - 1, r.core.clients());
  TEST_ASSERT_EQUAL(0, r.core.onOpen(&r.tr));
}

void test_extended_builder_output() {
  Rig r; buildIo(r.core.ui()); r.open(); r.hello();
  JsonDocument ui = r.tr.at(0, 1);
  JsonArray w = ui["w"].as<JsonArray>();
  TEST_ASSERT_EQUAL(17, w.size());
  TEST_ASSERT_TRUE(w[1]["center"].as<bool>());
  TEST_ASSERT_EQUAL(-100, w[1]["min"].as<int>());
  TEST_ASSERT_EQUAL_STRING("display", w[2]["ty"]);
  TEST_ASSERT_EQUAL(5, w[2]["digits"].as<int>());
  TEST_ASSERT_EQUAL_STRING("bar", w[2]["unit"]);
  TEST_ASSERT_TRUE(w[3]["rgb"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("clock", w[4]["ty"]);
  TEST_ASSERT_EQUAL_STRING("HH:mm:ss", w[4]["fmt"]);
  TEST_ASSERT_EQUAL_STRING("joystick", w[7]["ty"]);
  TEST_ASSERT_TRUE(w[7]["center"].as<bool>());
  TEST_ASSERT_TRUE(w[7]["exp"].as<bool>());
  TEST_ASSERT_TRUE(w[7]["sq"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("io", w[7]["page"]);
  TEST_ASSERT_EQUAL_STRING("inputs", w[7]["grp"]);
  TEST_ASSERT_EQUAL_STRING("dpad", w[8]["ty"]);
  TEST_ASSERT_EQUAL_STRING("color", w[9]["ty"]);
  TEST_ASSERT_EQUAL_STRING("time", w[10]["mode"]);
  TEST_ASSERT_EQUAL_STRING("flags", w[11]["ty"]);
  TEST_ASSERT_EQUAL(7, w[11]["opts"].size());
  TEST_ASSERT_EQUAL_STRING("Su", w[11]["opts"][6]);
  TEST_ASSERT_EQUAL(2, w[12]["cols"].size());
  TEST_ASSERT_EQUAL_STRING("Zone", w[12]["cols"][0]["lbl"]);
  TEST_ASSERT_EQUAL(2, w[12]["cols"][0]["w"].as<int>());
  TEST_ASSERT_EQUAL_STRING("right", w[12]["cols"][1]["align"]);
  TEST_ASSERT_EQUAL_STRING("https://example.com/a.png", w[13]["src"]);
  TEST_ASSERT_EQUAL_STRING("stream", w[14]["ty"]);
  TEST_ASSERT_EQUAL(14, w[15]["zoom"].as<int>());
  TEST_ASSERT_EQUAL(512, w[16]["maxlen"].as<int>());
  TEST_ASSERT_EQUAL(4, w[16]["rows"].as<int>());
  // initial values of the main page; dpad/image/stream carry none
  JsonDocument upd = r.tr.at(0, 2);
  TEST_ASSERT_EQUAL(0, upd["v"]["bal"].as<int>());
  TEST_ASSERT_EQUAL_STRING("", upd["v"]["disp"]);
  TEST_ASSERT_FALSE(upd["v"]["rgb"].as<bool>());
  TEST_ASSERT_EQUAL(0, upd["v"]["now"].as<int>());
  r.tr.clear(); r.sendMsg("{\"t\":\"page\",\"id\":\"io\"}");
  upd = r.tr.last();
  TEST_ASSERT_EQUAL(2, upd["v"]["joy"].size());
  TEST_ASSERT_EQUAL(0, upd["v"]["col"].as<int>());
  TEST_ASSERT_EQUAL(0, upd["v"]["start"].as<int>());
  TEST_ASSERT_EQUAL(0, upd["v"]["days"].as<int>());
  TEST_ASSERT_EQUAL(0, upd["v"]["tbl"].size());
  TEST_ASSERT_EQUAL(0, upd["v"]["pos"].size());
  TEST_ASSERT_EQUAL_STRING("", upd["v"]["notes"]);
  TEST_ASSERT_FALSE(upd["v"]["pad"].is<JsonVariant>());
  TEST_ASSERT_FALSE(upd["v"]["img"].is<JsonVariant>());
}

void test_extended_set_validation() {
  Rig r; buildIo(r.core.ui());
  Ui& ui = r.core.ui();
  int jx = 0, jy = 0, moves = 0; uint32_t col = 0; int days = -1; Str notes;
  ref(ui, "joy").onMove([&](int x, int y) { jx = x; jy = y; moves++; });
  ref(ui, "col").onChange([&](uint32_t v) { col = v; });
  ref(ui, "days").onChange([&](int v) { days = v; });
  ref(ui, "notes").onChange([&](const Str& v) { notes = v; });
  r.open(); r.hello(); r.sendMsg("{\"t\":\"page\",\"id\":\"io\"}"); r.tr.clear();
  auto rejected = [&](const char* msg) { r.sendMsg(msg); return r.tr.last()["t"] == "err" && r.tr.last()["code"].as<int>() == 7; };
  auto accepted = [&](const char* msg) { int n = r.tr.count(); r.sendMsg(msg); return r.tr.count() == n; };
  TEST_ASSERT_TRUE(accepted("{\"t\":\"set\",\"id\":\"joy\",\"v\":[10,-20]}"));
  TEST_ASSERT_EQUAL(10, jx); TEST_ASSERT_EQUAL(-20, jy); TEST_ASSERT_EQUAL(1, moves);
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"joy\",\"v\":[150,0]}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"joy\",\"v\":[1,2,3]}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"joy\",\"v\":5}"));
  TEST_ASSERT_EQUAL(1, moves);
  TEST_ASSERT_TRUE(accepted("{\"t\":\"set\",\"id\":\"col\",\"v\":16746496}"));   // 0xff8800
  TEST_ASSERT_EQUAL(0xff8800u, col);
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"col\",\"v\":16777216}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"col\",\"v\":-1}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"col\",\"v\":1.5}"));
  TEST_ASSERT_TRUE(accepted("{\"t\":\"set\",\"id\":\"days\",\"v\":127}"));
  TEST_ASSERT_EQUAL(127, days);
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"days\",\"v\":128}"));
  TEST_ASSERT_TRUE(accepted("{\"t\":\"set\",\"id\":\"start\",\"v\":21600}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"start\",\"v\":-5}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"start\",\"v\":\"6:00\"}"));
  TEST_ASSERT_TRUE(accepted("{\"t\":\"set\",\"id\":\"notes\",\"v\":\"hello\\nworld\"}"));
  TEST_ASSERT_EQUAL_STRING("hello\nworld", notes.c_str());
  Str longMsg = "{\"t\":\"set\",\"id\":\"notes\",\"v\":\""; for (int i = 0; i < 513; i++) longMsg += 'x'; longMsg += "\"}";
  TEST_ASSERT_TRUE(rejected(longMsg.c_str()));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"notes\",\"v\":3}"));
  // output widgets reject client sets, sketch sets work
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"tbl\",\"v\":[[\"a\",1]]}"));
  TEST_ASSERT_TRUE(rejected("{\"t\":\"set\",\"id\":\"rgb\",\"v\":true}"));
  TEST_ASSERT_TRUE(ui.set("rgb", true));
  TEST_ASSERT_TRUE(ui.set("rgb", 0xff0000));
  TEST_ASSERT_EQUAL(0xff0000, ui.get("rgb")->asInt());
  TEST_ASSERT_FALSE(ui.set("rgb", 0x1000000));
  TEST_ASSERT_FALSE(ui.set("rgb", -1));
  TEST_ASSERT_FALSE(ui.set("rgb", "red"));
  TEST_ASSERT_TRUE(ui.set("disp", 1.85f));
  TEST_ASSERT_TRUE(ui.set("disp", "Err"));
  TEST_ASSERT_TRUE(ui.set("bal", -40.f));
  TEST_ASSERT_FALSE(ui.set("bal", -140.f));
  TEST_ASSERT_TRUE(ui.set("joy", 5, -5));
  TEST_ASSERT_FALSE(ui.set("joy", 500, 0));
  TEST_ASSERT_FALSE(ui.set("tbl", "nope"));
  TEST_ASSERT_FALSE(ui.setRows("tbl", "{}"));
  // echoes arrive in one coalesced upd
  Client* c = r.core.client((uint8_t)r.slot); c->lastFlush -= 1000; r.tr.clear(); r.core.loop();
  JsonDocument upd = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("upd", upd["t"]);
  TEST_ASSERT_EQUAL(5, upd["v"]["joy"][0].as<int>());
  TEST_ASSERT_EQUAL(-5, upd["v"]["joy"][1].as<int>());
  TEST_ASSERT_EQUAL(0xff8800, upd["v"]["col"].as<int>());
  TEST_ASSERT_EQUAL(127, upd["v"]["days"].as<int>());
  TEST_ASSERT_EQUAL(21600, upd["v"]["start"].as<int>());
  TEST_ASSERT_EQUAL_STRING("hello\nworld", upd["v"]["notes"]);
  TEST_ASSERT_FALSE(upd["v"]["rgb"].is<JsonVariant>());   // main page, not visible
  r.sendMsg("{\"t\":\"page\",\"id\":\"main\"}");
  upd = r.tr.last();
  TEST_ASSERT_EQUAL(0xff0000, upd["v"]["rgb"].as<int>());
  TEST_ASSERT_EQUAL_STRING("Err", upd["v"]["disp"]);
  TEST_ASSERT_EQUAL(-40, upd["v"]["bal"].as<int>());
}

void test_dpad_events() {
  Rig r; buildIo(r.core.ui());
  std::vector<int> evs;
  ref(r.core.ui(), "pad").onEvent([&](int v) { evs.push_back(v); });
  r.open(); r.hello(); r.tr.clear();
  r.sendMsg("{\"t\":\"ev\",\"id\":\"pad\",\"v\":\"u\"}");
  r.sendMsg("{\"t\":\"ev\",\"id\":\"pad\",\"v\":0}");
  r.sendMsg("{\"t\":\"ev\",\"id\":\"pad\",\"v\":\"c\"}");
  r.sendMsg("{\"t\":\"ev\",\"id\":\"pad\",\"v\":\"r\"}");
  TEST_ASSERT_EQUAL(4, evs.size());
  TEST_ASSERT_EQUAL('u', evs[0]); TEST_ASSERT_EQUAL(0, evs[1]); TEST_ASSERT_EQUAL('c', evs[2]); TEST_ASSERT_EQUAL('r', evs[3]);
  TEST_ASSERT_EQUAL(0, r.tr.count());
  r.sendMsg("{\"t\":\"ev\",\"id\":\"joy\"}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"set\",\"id\":\"pad\",\"v\":1}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
}

void test_clock_push() {
  Rig r; buildIo(r.core.ui()); r.open(); r.hello();
  r.core.loop();
  TEST_ASSERT_EQUAL(0, r.core.ui().get("now")->asInt());   // no time source yet
  r.sendMsg("{\"t\":\"time\",\"unix\":1728700000,\"tz\":120}");
  Client* c = r.core.client((uint8_t)r.slot); c->lastFlush -= 1000; r.tr.clear();
  r.core.loop();
  TEST_ASSERT_EQUAL(1728700000, r.core.ui().get("now")->asInt());
  JsonDocument upd = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("upd", upd["t"]);
  TEST_ASSERT_EQUAL(1728700000u, upd["v"]["now"].as<uint32_t>());
  // a fresh client gets the clock in its initial upd
  int s2 = r.core.onOpen(&r.tr);
  r.core.onMessage((uint8_t)s2, "{\"t\":\"hello\",\"v\":1,\"client\":\"web\"}", 36);
  TEST_ASSERT_EQUAL(1728700000u, r.tr.at((uint8_t)s2, 2)["v"]["now"].as<uint32_t>());
  // sketch time overrides the client clock and is pushed on the next loop
  r.core.setTime(1728800000, true); c->lastFlush -= 1000; r.tr.clear(); r.core.loop();
  TEST_ASSERT_EQUAL(1728800000u, r.tr.last()["v"]["now"].as<uint32_t>());
}

void test_table_and_map_setters() {
  Rig r; buildIo(r.core.ui()); r.open(); r.hello(); r.sendMsg("{\"t\":\"page\",\"id\":\"io\"}"); r.tr.clear();
  Ui& ui = r.core.ui();
  TEST_ASSERT_TRUE(ui.setRows("tbl", "[[\"Kitchen\",21.5],[\"Bath\",23],[\"Hall\",19.8]]"));
  TEST_ASSERT_TRUE(ui.setPoints("pos", "[[52.52,13.405,\"Boiler\"]]"));
  TEST_ASSERT_FALSE(ui.setRows("joy", "[[1,2]]"));
  Client* c = r.core.client((uint8_t)r.slot); c->lastFlush -= 1000; r.core.loop();
  JsonDocument upd = r.tr.last();
  TEST_ASSERT_EQUAL(3, upd["v"]["tbl"].size());
  TEST_ASSERT_EQUAL_STRING("Bath", upd["v"]["tbl"][1][0]);
  TEST_ASSERT_EQUAL_FLOAT(21.5f, upd["v"]["tbl"][0][1].as<float>());
  TEST_ASSERT_EQUAL_STRING("Boiler", upd["v"]["pos"][0][2]);
  TEST_ASSERT_EQUAL_FLOAT(13.405f, upd["v"]["pos"][0][1].as<float>());
  // unchanged rows are not re-sent
  TEST_ASSERT_TRUE(ui.setRows("tbl", "[[\"Kitchen\",21.5],[\"Bath\",23],[\"Hall\",19.8]]"));
  c->lastFlush -= 1000; r.tr.clear(); r.core.loop();
  TEST_ASSERT_EQUAL(0, r.tr.count());
  ui.setRows("tbl", "[]"); c->lastFlush -= 1000; r.core.loop();
  TEST_ASSERT_EQUAL(0, r.tr.last()["v"]["tbl"].size());
  ui.prop("img").src("https://example.com/b.png");
  TEST_ASSERT_EQUAL_STRING("https://example.com/b.png", r.tr.last()["p"]["src"]);
}

int main() {
  mkdir("test_output", 0755);
  g_out = fopen("test_output/d2c.jsonl", "w");
  UNITY_BEGIN();
  RUN_TEST(test_hmac_vector);
  RUN_TEST(test_json_writer_escapes);
  RUN_TEST(test_hello_without_pin_sends_ui_and_upd);
  RUN_TEST(test_pin_flow_wrong_then_right_then_token);
  RUN_TEST(test_lockout_after_five_failures);
  RUN_TEST(test_set_validation_callbacks_and_bind);
  RUN_TEST(test_events_hold_and_click);
  RUN_TEST(test_persist_restores_value);
  RUN_TEST(test_page_filter);
  RUN_TEST(test_dialogs_props_toast_log_chart);
  RUN_TEST(test_sys_info_time_reboot_and_errors);
  RUN_TEST(test_multiple_uis_per_transport_and_pin_override);
  RUN_TEST(test_max_clients);
  RUN_TEST(test_extended_builder_output);
  RUN_TEST(test_extended_set_validation);
  RUN_TEST(test_dpad_events);
  RUN_TEST(test_clock_push);
  RUN_TEST(test_table_and_map_setters);
  if (g_out) fclose(g_out);
  return UNITY_END();
}
