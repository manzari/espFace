// Native unit tests for the espFace core. Every device message is appended to test_output/d2c.jsonl
// so the protocol validator can schema-check them afterwards.
#include <unity.h>
#include <ArduinoJson.h>
#include <stdio.h>
#include <sys/stat.h>
#include <vector>
#include <algorithm>
#include <unistd.h>
#include "core/Core.h"
#include "sys/Info.h"
#include "sys/Ntfy.h"
#include "sys/Ota.h"
#include "util/Hmac.h"
#include "transport/LineFramer.h"
#include "transport/BleFramer.h"
#include "transport/StreamTransport.h"

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
  bool supportsBinary() const override { return true; }   // stands in for the WebSocket transport
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

// ---- phase 4: system pages --------------------------------------------------------
struct MockUpdate : public OtaBackend {
  std::vector<uint8_t> data; Str md5; size_t size = 0; bool ended = false, aborted = false, failWrite = false;
  bool begin(size_t s, const char* m) override { size = s; md5 = m ? m : ""; data.clear(); ended = aborted = false; return s != 7; }   // 7 = "does not fit"
  size_t write(const uint8_t* d, size_t n) override { if (failWrite) return 0; data.insert(data.end(), d, d + n); return n; }
  bool end() override { ended = true; return md5 == "0123456789abcdef0123456789abcdef"; }
  void abort() override { aborted = true; data.clear(); }
  const char* error() const override { return ended ? "md5 mismatch" : "write failed"; }
};

struct OtaRig : public Rig {
  MockUpdate upd; Ota ota;
  OtaRig() : Rig() {
    ota.begin(&core, &upd, &store);
    core.sysHook = [this](uint8_t slot, const char* cmd, void* doc) { return ota.handleSys(slot, cmd, doc); };
    core.binaryHook = [this](uint8_t slot, const uint8_t* d, size_t n) { return ota.onBinary(slot, d, n); };
    core.closeHook = [this](uint8_t slot) { ota.onClose(slot); };
    core.addCap("ota"); core.addCap("otaurl");
    open(); hello(); tr.clear();
  }
  void bin(const char* bytes, int s = -1) { core.onBinary((uint8_t)(s < 0 ? slot : s), (const uint8_t*)bytes, strlen(bytes)); }
  void beginOta(int size, const char* md5 = "0123456789abcdef0123456789abcdef") {
    char m[160]; snprintf(m, sizeof m, "{\"t\":\"sys\",\"cmd\":\"ota.begin\",\"size\":%d,\"md5\":\"%s\"}", size, md5); sendMsg(m);
  }
};

void test_caps_gating() {
  Rig r; r.open(); r.hello();
  JsonDocument h = r.tr.at(0, 0);
  TEST_ASSERT_EQUAL(4, h["caps"].size());
  for (const char* c : {"pin", "reboot", "info", "chart"}) TEST_ASSERT_TRUE(r.core.hasCap(c));
  for (const char* c : {"ota", "otaurl", "wifi", "ntp", "ntfy"}) TEST_ASSERT_FALSE(r.core.hasCap(c));
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.begin\",\"size\":10,\"md5\":\"0123456789abcdef0123456789abcdef\"}");
  TEST_ASSERT_EQUAL(8, r.tr.last()["code"].as<int>());
  TEST_ASSERT_EQUAL_STRING("ota.begin", r.tr.last()["ref"]);
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.url\",\"url\":\"http://x/fw.bin\"}");
  TEST_ASSERT_EQUAL(8, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"wifi.set\",\"ssid\":\"Home\"}");
  TEST_ASSERT_EQUAL(8, r.tr.last()["code"].as<int>());
  r.core.addCap("ota"); r.core.addCap("ota"); r.core.addCap("ntp");
  int s2 = r.core.onOpen(&r.tr); r.core.onMessage((uint8_t)s2, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  TEST_ASSERT_EQUAL(6, r.tr.at((uint8_t)s2, 0)["caps"].size());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.begin\",\"size\":10,\"md5\":\"0123456789abcdef0123456789abcdef\"}");
  TEST_ASSERT_EQUAL(8, r.tr.last()["code"].as<int>());   // cap present but no handler installed
  r.core.removeCap("ota"); r.core.removeCap("nope");
  TEST_ASSERT_FALSE(r.core.hasCap("ota"));
  TEST_ASSERT_TRUE(r.core.hasCap("ntp"));
}

void test_ota_push_state_machine() {
  OtaRig r;
  r.beginOta(10);
  TEST_ASSERT_EQUAL_STRING("ota.begin", r.tr.last()["cmd"]);
  TEST_ASSERT_TRUE(r.tr.last()["ok"].as<bool>());
  TEST_ASSERT_TRUE(r.ota.busy());
  TEST_ASSERT_EQUAL(10, r.upd.size);
  r.beginOta(10);
  TEST_ASSERT_EQUAL(9, r.tr.last()["code"].as<int>());
  r.beginOta(10, "zz");
  TEST_ASSERT_EQUAL(9, r.tr.last()["code"].as<int>());   // busy wins over validation
  r.tr.clear();
  r.bin("abcdef");
  JsonDocument p = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("ota.progress", p["cmd"]);
  TEST_ASSERT_EQUAL(60, p["pct"].as<int>());
  r.bin("ghij");
  TEST_ASSERT_FALSE(r.ota.busy());
  JsonDocument d = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("ota.done", d["cmd"]);
  TEST_ASSERT_TRUE(d["ok"].as<bool>());
  TEST_ASSERT_EQUAL(100, r.tr.at(0, r.tr.count() - 2)["pct"].as<int>());
  TEST_ASSERT_EQUAL(10, r.upd.data.size());
  TEST_ASSERT_EQUAL_MEMORY("abcdefghij", r.upd.data.data(), 10);
  TEST_ASSERT_TRUE(r.core.rebootPending());
  Str marker; TEST_ASSERT_TRUE(r.store.getStr("rr", marker));
  TEST_ASSERT_EQUAL_STRING("ota", marker.c_str());
  // binary without a session
  r.bin("x");
  TEST_ASSERT_EQUAL(10, r.tr.last()["code"].as<int>());
  // validation
  r.beginOta(0); TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.beginOta(10, "0123456789ABCDEF0123456789abcdef"); TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.begin\",\"size\":10,\"md5\":\"0123456789abcdef0123456789abcdef\",\"kind\":\"fs\"}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.beginOta(7); TEST_ASSERT_EQUAL(10, r.tr.last()["code"].as<int>());   // backend refused
  TEST_ASSERT_FALSE(r.ota.busy());
  // md5 mismatch
  r.beginOta(3, "ffffffffffffffffffffffffffffffff"); r.bin("abc");
  d = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("ota.done", d["cmd"]);
  TEST_ASSERT_FALSE(d["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("md5 mismatch", d["msg"]);
  // write failure
  r.upd.failWrite = true; r.beginOta(4); r.bin("ab");
  TEST_ASSERT_FALSE(r.tr.last()["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("write failed", r.tr.last()["msg"]);
  TEST_ASSERT_TRUE(r.upd.aborted);
  r.upd.failWrite = false;
  // abort
  r.beginOta(4); r.upd.aborted = false;
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.abort\"}");
  TEST_ASSERT_TRUE(r.tr.last()["ok"].as<bool>());
  TEST_ASSERT_TRUE(r.upd.aborted);
  TEST_ASSERT_FALSE(r.ota.busy());
  r.bin("ab"); TEST_ASSERT_EQUAL(10, r.tr.last()["code"].as<int>());
  // another client cannot feed the session; a disconnect of the owner aborts it
  r.beginOta(4);
  int s2 = r.core.onOpen(&r.tr); r.core.onMessage((uint8_t)s2, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  r.bin("ab", s2);
  TEST_ASSERT_EQUAL(10, r.tr.last((uint8_t)s2)["code"].as<int>());
  TEST_ASSERT_TRUE(r.ota.busy());
  r.core.onClose((uint8_t)r.slot);
  TEST_ASSERT_FALSE(r.ota.busy());
  r.open(); r.hello();
  // timeout
  r.beginOta(4); r.ota.setTimeout(1); usleep(3000); r.ota.loop();
  TEST_ASSERT_FALSE(r.ota.busy());
  TEST_ASSERT_EQUAL_STRING("timeout", r.tr.last()["msg"]);
}

void test_ota_url() {
  OtaRig r;
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.url\",\"url\":\"ftp://x/fw.bin\"}");
  TEST_ASSERT_EQUAL(7, r.tr.last()["code"].as<int>());
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.url\",\"url\":\"https://x/fw.bin\"}");
  TEST_ASSERT_EQUAL(10, r.tr.last()["code"].as<int>());   // no downloader on native
  Str seen;
  r.ota.urlFetch = [&](const char* url) {
    seen = url;
    if (!r.ota.start(-1, 4, nullptr)) return false;
    r.ota.feed((const uint8_t*)"ab", 2); r.ota.feed((const uint8_t*)"cd", 2);
    return r.ota.finish();
  };
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"ota.url\",\"url\":\"https://x/fw.bin\"}");
  TEST_ASSERT_EQUAL_STRING("https://x/fw.bin", seen.c_str());
  int ok = r.tr.find("\"ota.url\",\"ok\":true");
  TEST_ASSERT_TRUE(ok >= 0);
  TEST_ASSERT_EQUAL_STRING("ota.done", r.tr.last()["cmd"]);
  TEST_ASSERT_FALSE(r.tr.last()["ok"].as<bool>());   // mock verifies against the fixed md5
  TEST_ASSERT_EQUAL(4, r.upd.data.size());
}

void test_reset_reason_mapping() {
  TEST_ASSERT_EQUAL_STRING("power", resetReasonName(1, false));
  TEST_ASSERT_EQUAL_STRING("button", resetReasonName(2, false));
  TEST_ASSERT_EQUAL_STRING("sw", resetReasonName(3, false));
  TEST_ASSERT_EQUAL_STRING("ota", resetReasonName(3, true));
  TEST_ASSERT_EQUAL_STRING("panic", resetReasonName(4, false));
  TEST_ASSERT_EQUAL_STRING("wdt", resetReasonName(5, false));
  TEST_ASSERT_EQUAL_STRING("wdt", resetReasonName(6, true));
  TEST_ASSERT_EQUAL_STRING("wdt", resetReasonName(7, false));
  TEST_ASSERT_EQUAL_STRING("brownout", resetReasonName(9, false));
  TEST_ASSERT_EQUAL_STRING("other", resetReasonName(0, false));
  TEST_ASSERT_EQUAL_STRING("other", resetReasonName(8, false));
  TEST_ASSERT_EQUAL_STRING("other", resetReasonName(99, true));
}

void test_info_fields() {
  Rig r; r.open(); r.hello(); r.tr.clear();
  r.core.infoFill = [](JsonWriter& jw) {
    InfoData d; d.chip = "ESP32-S3"; d.rr = "ota"; d.heap = 180000; d.heapmin = 150000;
    d.ip = "192.168.1.50"; d.ssid = "Home"; d.rssi = -61; d.hasRssi = true; d.mac = "aa:bb:cc:dd:ee:ff";
    writeInfo(jw, d);
  };
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"info\"}");
  JsonDocument i = r.tr.last();
  TEST_ASSERT_EQUAL_STRING("ESP32-S3", i["chip"]);
  TEST_ASSERT_EQUAL_STRING("ota", i["rr"]);
  TEST_ASSERT_EQUAL(180000, i["heap"].as<int>());
  TEST_ASSERT_EQUAL(150000, i["heapmin"].as<int>());
  TEST_ASSERT_EQUAL_STRING("192.168.1.50", i["ip"]);
  TEST_ASSERT_EQUAL_STRING("Home", i["ssid"]);
  TEST_ASSERT_EQUAL(-61, i["rssi"].as<int>());
  TEST_ASSERT_EQUAL_STRING("aa:bb:cc:dd:ee:ff", i["mac"]);
  TEST_ASSERT_EQUAL_STRING("1.0.0", i["fw"]);
  TEST_ASSERT_TRUE(i["up"].is<unsigned long>());
  // AP mode: no rssi, no ip of a station
  r.core.infoFill = [](JsonWriter& jw) { InfoData d; d.chip = "ESP32"; d.rr = "power"; writeInfo(jw, d); };
  r.sendMsg("{\"t\":\"sys\",\"cmd\":\"info\"}");
  i = r.tr.last();
  TEST_ASSERT_FALSE(i["rssi"].is<int>());
  TEST_ASSERT_FALSE(i["ip"].is<const char*>());
  TEST_ASSERT_EQUAL(0, i["heap"].as<int>());
}

void test_ntfy_rate_limit() {
  Notifier n; int sends = 0; Str lastTitle; uint8_t lastPrio = 0;
  n.sender = [&](const Notifier::Msg& m) { sends++; lastTitle = m.title; lastPrio = m.prio; n.busy = false; };
  TEST_ASSERT_FALSE(n.configured());
  TEST_ASSERT_FALSE(n.notify("a", "b", Ntfy::Default, 1000));
  n.configure("https://ntfy.sh/", "boiler", nullptr);
  TEST_ASSERT_EQUAL_STRING("https://ntfy.sh", n.server().c_str());
  TEST_ASSERT_TRUE(n.notify("first", "x", Ntfy::High, 1000));
  TEST_ASSERT_EQUAL(1, sends);
  TEST_ASSERT_EQUAL_STRING("first", lastTitle.c_str());
  TEST_ASSERT_EQUAL(4, lastPrio);
  TEST_ASSERT_TRUE(n.notify("second", "y", Ntfy::Low, 2000));
  TEST_ASSERT_EQUAL(1, sends);
  TEST_ASSERT_EQUAL(1, n.queued());
  n.loop(5000); TEST_ASSERT_EQUAL(1, sends);
  n.loop(10999); TEST_ASSERT_EQUAL(1, sends);
  n.loop(11000); TEST_ASSERT_EQUAL(2, sends);
  TEST_ASSERT_EQUAL_STRING("second", lastTitle.c_str());
  TEST_ASSERT_EQUAL(0, n.queued());
  for (int i = 0; i < 4; i++) TEST_ASSERT_TRUE(n.notify("q", "z", Ntfy::Min, 11000));
  TEST_ASSERT_FALSE(n.notify("overflow", "z", Ntfy::Min, 11000));
  TEST_ASSERT_EQUAL(4, n.queued());
  n.setRateLimit(1000);
  n.loop(12000); TEST_ASSERT_EQUAL(3, sends);
  n.busy = true; n.loop(13000); TEST_ASSERT_EQUAL(3, sends);   // a POST still in flight
  n.busy = false; n.loop(13000); TEST_ASSERT_EQUAL(4, sends);
  TEST_ASSERT_EQUAL(2, n.queued());
  TEST_ASSERT_EQUAL(4, n.sent());
}

// ---- phase 5: streams and BLE framing -------------------------------------------------
void test_line_framer() {
  LineFramer lf(16);
  std::vector<Str> lines; int over = 0;
  auto feed = [&](const char* s) {
    for (const char* p = s; *p; p++) { auto r = lf.feed((uint8_t)*p); if (r == LineFramer::Line) lines.push_back(Str(lf.data(), lf.len())); else if (r == LineFramer::Oversize) over++; }
  };
  feed("{\"a\":1}\r\n\r\n\n{\"b\":");
  TEST_ASSERT_EQUAL(1, lines.size());
  TEST_ASSERT_EQUAL_STRING("{\"a\":1}", lines[0].c_str());
  feed("2}\n{\"c\":3}\n{\"d\":4}");                          // split and joined deliveries
  TEST_ASSERT_EQUAL(3, lines.size());
  TEST_ASSERT_EQUAL_STRING("{\"b\":2}", lines[1].c_str());
  TEST_ASSERT_EQUAL_STRING("{\"c\":3}", lines[2].c_str());
  feed("\n");
  TEST_ASSERT_EQUAL_STRING("{\"d\":4}", lines[3].c_str());
  TEST_ASSERT_EQUAL(7, lf.len());
  feed("0123456789abcdef\n");                                // exactly cap: fine
  TEST_ASSERT_EQUAL(5, lines.size()); TEST_ASSERT_EQUAL(0, over);
  feed("0123456789abcdefX\n{\"e\":5}\n");                     // one over cap: dropped, reported once, next line intact
  TEST_ASSERT_EQUAL(1, over);
  TEST_ASSERT_EQUAL(6, lines.size());
  TEST_ASSERT_EQUAL_STRING("{\"e\":5}", lines[5].c_str());
  feed("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n");
  TEST_ASSERT_EQUAL(2, over); TEST_ASSERT_EQUAL(6, lines.size());
}

static Str bigMsg(size_t n, char seed) { Str m = "{\"t\":\"x\",\"p\":\""; while (m.length() < n - 2) m += (char)('a' + (seed + m.length()) % 26); m += "\"}"; return m; }
using Pkts = std::vector<std::vector<uint8_t>>;

// Sends a message through the chunker in FrameSink-sized frames and collects the packets.
static void chunkMsg(BleChunker& ch, const Str& m, Pkts& pkts) {
  size_t off = 0;
  do {
    size_t take = m.length() - off; if (take > ESPFACE_FRAME_SIZE) take = ESPFACE_FRAME_SIZE;
    bool last = off + take >= m.length();
    TEST_ASSERT_TRUE(ch.frame(m.c_str() + off, take, last, [&](const uint8_t* p, size_t n) { pkts.push_back(std::vector<uint8_t>(p, p + n)); return true; }));
    off += take;
  } while (off < m.length());
}

void test_ble_framer_roundtrip_and_mtu() {
  for (uint16_t mtu : {(uint16_t)23, (uint16_t)185, (uint16_t)512, (uint16_t)1000}) {
    BleChunker ch(mtu); BleReassembler re;
    size_t pay = mtu > 512 ? 509 : (size_t)mtu - 3;
    TEST_ASSERT_EQUAL(pay, ch.payloadMax());
    int got = 0; size_t maxPkt = 0;
    for (int i = 0; i < 300; i++) {                                // 300 messages wrap seq several times
      Str m = bigMsg(10 + (i * 37) % 1900, (char)i);
      Pkts pkts; chunkMsg(ch, m, pkts);
      TEST_ASSERT_EQUAL((m.length() + pay - 1) / pay, pkts.size());
      TEST_ASSERT_TRUE(pkts.front()[1] & BLE_FLAG_FIRST);
      TEST_ASSERT_TRUE(pkts.back()[1] & BLE_FLAG_LAST);
      for (size_t k = 0; k < pkts.size(); k++) {
        if (pkts[k].size() > maxPkt) maxPkt = pkts[k].size();
        if (k) TEST_ASSERT_EQUAL((uint8_t)(pkts[k - 1][0] + 1), pkts[k][0]);
        auto r = re.feed(pkts[k].data(), pkts[k].size());
        if (k + 1 < pkts.size()) { TEST_ASSERT_EQUAL(BleReassembler::None, r); TEST_ASSERT_TRUE(re.partial()); }
        else { TEST_ASSERT_EQUAL(BleReassembler::Message, r); TEST_ASSERT_EQUAL(m.length(), re.len()); TEST_ASSERT_EQUAL_STRING(m.c_str(), re.data()); got++; }
      }
    }
    TEST_ASSERT_EQUAL(300, got);
    TEST_ASSERT_EQUAL(pay + 2, maxPkt);
  }
  // a message delivered in several small frames fills packets across frame boundaries
  BleChunker ch(103); Pkts pkts;
  auto collect = [&](const uint8_t* p, size_t n) { pkts.push_back(std::vector<uint8_t>(p, p + n)); return true; };
  for (int i = 0; i < 10; i++) ch.frame("0123456789", 10, i == 9, collect);
  TEST_ASSERT_EQUAL(1, pkts.size()); TEST_ASSERT_EQUAL(102, pkts[0].size());
  TEST_ASSERT_EQUAL(BLE_FLAG_FIRST | BLE_FLAG_LAST, pkts[0][1]);
  pkts.clear();
  for (int i = 0; i < 11; i++) ch.frame("0123456789", 10, i == 10, collect);
  TEST_ASSERT_EQUAL(2, pkts.size()); TEST_ASSERT_EQUAL(102, pkts[0].size()); TEST_ASSERT_EQUAL(12, pkts[1].size());
  TEST_ASSERT_EQUAL(BLE_FLAG_FIRST, pkts[0][1]); TEST_ASSERT_EQUAL(BLE_FLAG_LAST, pkts[1][1]);
  TEST_ASSERT_FALSE(ch.frame("abc", 3, true, [](const uint8_t*, size_t) { return false; }));   // emit failure aborts
}

void test_ble_framer_gap_duplicate_oversize() {
  BleChunker ch(23); BleReassembler re(100);
  Str m = bigMsg(60, 1);
  Pkts pkts; chunkMsg(ch, m, pkts);
  TEST_ASSERT_EQUAL(3, pkts.size());
  auto feed = [&](Pkts& p, size_t k) { return re.feed(p[k].data(), p[k].size()); };
  // gap: second packet lost -> third reports Dropped, partial gone
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 0));
  TEST_ASSERT_EQUAL(BleReassembler::Dropped, feed(pkts, 2));
  TEST_ASSERT_FALSE(re.partial());
  TEST_ASSERT_EQUAL(BleReassembler::Dropped, feed(pkts, 1));           // stray continuation without a start
  // duplicates are ignored, the message still completes
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 0));
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 0));
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 1));
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 1));
  TEST_ASSERT_EQUAL(BleReassembler::Message, feed(pkts, 2));
  TEST_ASSERT_EQUAL_STRING(m.c_str(), re.data());
  // out of order (2 before 1) drops the message; a fresh start recovers
  TEST_ASSERT_EQUAL(BleReassembler::None, feed(pkts, 0));
  TEST_ASSERT_EQUAL(BleReassembler::Dropped, feed(pkts, 2));
  TEST_ASSERT_EQUAL(BleReassembler::Dropped, feed(pkts, 1));
  for (size_t k = 0; k < 3; k++) feed(pkts, k);
  TEST_ASSERT_EQUAL_STRING(m.c_str(), re.data());
  // oversize: reported once at the overflowing chunk, the rest of that message is skipped, the next one is intact
  Str big = bigMsg(150, 2); Pkts bp; chunkMsg(ch, big, bp);
  TEST_ASSERT_EQUAL(8, bp.size());
  int over = 0, none = 0;
  for (size_t k = 0; k < bp.size(); k++) { auto r = feed(bp, k); if (r == BleReassembler::Oversize) over++; else if (r == BleReassembler::None) none++; }
  TEST_ASSERT_EQUAL(1, over); TEST_ASSERT_EQUAL(7, none);
  pkts.clear(); chunkMsg(ch, m, pkts);
  for (size_t k = 0; k < 3; k++) feed(pkts, k);
  TEST_ASSERT_EQUAL_STRING(m.c_str(), re.data());
  // seq wrap inside one message
  BleChunker w(23); BleReassembler wr(8192);
  Str wide = bigMsg(20 * 260, 3); Pkts wp; chunkMsg(w, wide, wp);
  TEST_ASSERT_EQUAL(260, wp.size());
  TEST_ASSERT_EQUAL(wp[0][0], wp[256][0]);
  BleReassembler::Result last = BleReassembler::None;
  for (auto& p : wp) last = wr.feed(p.data(), p.size());
  TEST_ASSERT_EQUAL(BleReassembler::Message, last);
  TEST_ASSERT_EQUAL(wide.length(), wr.len());
  TEST_ASSERT_EQUAL(BleReassembler::Dropped, wr.feed(wp[0].data(), 1));   // runt packet
}

// Fake Arduino Stream: the test writes client lines into rx, device output lands in lines.
struct FakeStream : public StreamIo {
  std::vector<uint8_t> rx; size_t pos = 0; Str tx; std::vector<Str> lines;
  int available() override { return (int)(rx.size() - pos); }
  int read() override { return pos < rx.size() ? rx[pos++] : -1; }
  size_t write(const uint8_t* d, size_t n) override {
    for (size_t i = 0; i < n; i++) { if (d[i] == '\n') { lines.push_back(tx); if (g_out) fprintf(g_out, "%s\n", tx.c_str()); tx = ""; } else tx += (char)d[i]; }
    return n;
  }
  void push(const char* s) { rx.insert(rx.end(), (const uint8_t*)s, (const uint8_t*)s + strlen(s)); }
  JsonDocument last() { JsonDocument d; deserializeJson(d, lines.back()); return d; }
  JsonDocument at(int i) { JsonDocument d; deserializeJson(d, lines[i]); return d; }
  int find(const char* needle, int from = 0) { for (int i = from; i < (int)lines.size(); i++) if (strstr(lines[i].c_str(), needle)) return i; return -1; }
};

struct StreamRig {
  MemStore store; FakeStream io; StreamTransport tr; Core core;
  StreamRig(const char* pin = nullptr) : tr(io, "serial") {
    core.setId("a1b2c3").setVersion("1.0.0");
    core.begin("Test", &store);
    core.addTransport(&tr);               // added after begin: started immediately
    if (pin) core.setPin(pin, true);
  }
  void send(const char* line) { io.push(line); core.loop(); }
};

void test_stream_transport_end_to_end() {
  StreamRig r("1234");
  r.core.ui().gauge("temp", "T", 0, 100); r.core.ui().sw("pump", "Pump");
  TEST_ASSERT_FALSE(r.tr.open());
  r.send("\r\n\n");                                   // noise does not open a session
  TEST_ASSERT_FALSE(r.tr.open()); TEST_ASSERT_EQUAL(0, r.io.lines.size());
  r.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\r\n");
  TEST_ASSERT_TRUE(r.tr.open());
  JsonDocument h = r.io.last();
  TEST_ASSERT_EQUAL_STRING("hello", h["t"]); TEST_ASSERT_FALSE(h["ok"].as<bool>()); TEST_ASSERT_EQUAL_STRING("pin", h["auth"]);
  char mac[65]; pinMac("1234", h["nonce"], "a1b2c3", mac);
  Str a = "{\"t\":\"auth\",\"mac\":\""; a += mac; a += "\"}\n"; r.send(a.c_str());
  int ai = r.io.find("\"t\":\"auth\""); TEST_ASSERT_TRUE(ai >= 0);
  TEST_ASSERT_TRUE(r.io.at(ai)["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("ui", r.io.at(ai + 1)["t"]); TEST_ASSERT_EQUAL_STRING("upd", r.io.at(ai + 2)["t"]);
  TEST_ASSERT_EQUAL(1, r.core.clients());
  TEST_ASSERT_EQUAL_STRING("serial", r.core.client((uint8_t)r.tr.slot())->tr->name());
  // set in two deliveries, then the flush pushes the new value as one line
  r.send("{\"t\":\"set\",\"id\":\"pu"); r.send("mp\",\"v\":true}\n");
  TEST_ASSERT_TRUE(r.core.ui().get("pump")->asBool());
  r.core.client((uint8_t)r.tr.slot())->lastFlush -= 1000; r.core.ui().set("temp", 42.5f); r.core.loop();
  TEST_ASSERT_EQUAL_STRING("upd", r.io.last()["t"]); TEST_ASSERT_EQUAL_FLOAT(42.5f, r.io.last()["v"]["temp"].as<float>());
  TEST_ASSERT_EQUAL(0, r.io.tx.length());                     // every message ends with a newline
  // oversize line -> err 2, session intact; then two joined lines in one delivery
  Str big = "{\"t\":\"set\",\"id\":\"pump\",\"v\":\""; while (big.length() < ESPFACE_MAX_MSG + 10) big += "x"; big += "\"}\n";
  r.send(big.c_str());
  TEST_ASSERT_EQUAL(2, r.io.last()["code"].as<int>());
  r.send("{\"t\":\"set\",\"id\":\"pump\",\"v\":false}\n{\"t\":\"set\",\"id\":\"nope\",\"v\":1}\n");
  TEST_ASSERT_FALSE(r.core.ui().get("pump")->asBool());
  TEST_ASSERT_EQUAL(6, r.io.last()["code"].as<int>());
  // a new hello on the same wire restarts the session: not authenticated any more
  int before = (int)r.io.lines.size();
  r.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n");
  TEST_ASSERT_EQUAL(before + 1, (int)r.io.lines.size());
  TEST_ASSERT_FALSE(r.io.last()["ok"].as<bool>()); TEST_ASSERT_EQUAL(0, r.core.clients());
  r.send("{\"t\":\"set\",\"id\":\"pump\",\"v\":true}\n");
  TEST_ASSERT_EQUAL(3, r.io.last()["code"].as<int>());
  // a close requested by the core is applied in the next loop
  r.tr.close((uint8_t)r.tr.slot()); TEST_ASSERT_TRUE(r.tr.open()); r.core.loop(); TEST_ASSERT_FALSE(r.tr.open());
  // idle timeout
  r.tr.setIdleTimeout(1);
  r.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n"); TEST_ASSERT_TRUE(r.tr.open());
  uint32_t t0 = nowMs(); while (nowMs() - t0 < 3) {}
  r.core.loop(); TEST_ASSERT_FALSE(r.tr.open());
  r.tr.setIdleTimeout(0);
  // open on begin, and too-many-clients as a raw err line when no slot is free
  FakeStream io2; StreamTransport t2(io2, "uart"); t2.setOpenOnBegin(true); r.core.addTransport(&t2);
  TEST_ASSERT_TRUE(t2.open());
  for (int i = 0; i < ESPFACE_MAX_CLIENTS - 1; i++) r.core.onOpen(&r.tr);
  r.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n");
  TEST_ASSERT_FALSE(r.tr.open()); TEST_ASSERT_EQUAL(9, r.io.last()["code"].as<int>());
}

void test_ota_begin_refused_on_stream() {
  StreamRig r; MockUpdate upd; Ota ota; Str seen;
  ota.begin(&r.core, &upd, &r.store);
  r.core.sysHook = [&](uint8_t slot, const char* cmd, void* doc) { return ota.handleSys(slot, cmd, doc); };
  ota.urlFetch = [&](const char* url) { seen = url; return true; };
  r.core.addCap("ota"); r.core.addCap("otaurl");
  r.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n");
  TEST_ASSERT_EQUAL_STRING("upd", r.io.last()["t"]);
  r.send("{\"t\":\"sys\",\"cmd\":\"ota.begin\",\"size\":10,\"md5\":\"0123456789abcdef0123456789abcdef\"}\n");
  TEST_ASSERT_EQUAL_STRING("err", r.io.last()["t"]);
  TEST_ASSERT_EQUAL(8, r.io.last()["code"].as<int>()); TEST_ASSERT_EQUAL_STRING("ota.begin", r.io.last()["ref"]);
  TEST_ASSERT_FALSE(ota.busy());
  r.send("{\"t\":\"sys\",\"cmd\":\"ota.url\",\"url\":\"http://x/fw.bin\"}\n");
  TEST_ASSERT_EQUAL_STRING("http://x/fw.bin", seen.c_str());
  TEST_ASSERT_EQUAL_STRING("ota.url", r.io.last()["cmd"]); TEST_ASSERT_TRUE(r.io.last()["ok"].as<bool>());
  r.send("{\"t\":\"sys\",\"cmd\":\"ota.abort\"}\n");
  TEST_ASSERT_TRUE(r.io.last()["ok"].as<bool>());
}

// ---- phase 6: hardening -------------------------------------------------------------------
#include <dirent.h>
#include <malloc.h>
#if defined(__SANITIZE_ADDRESS__) || (defined(__has_feature) && __has_feature(address_sanitizer))
extern "C" size_t __sanitizer_get_current_allocated_bytes();
static size_t heapNow() { return __sanitizer_get_current_allocated_bytes(); }
static const char* heapSource() { return "asan allocator"; }
#else
static size_t g_live = 0;
void* operator new(size_t n) { void* p = malloc(n); g_live += malloc_usable_size(p); return p; }
void* operator new[](size_t n) { void* p = malloc(n); g_live += malloc_usable_size(p); return p; }
void operator delete(void* p) noexcept { if (p) g_live -= malloc_usable_size(p); free(p); }
void operator delete[](void* p) noexcept { if (p) g_live -= malloc_usable_size(p); free(p); }
void operator delete(void* p, size_t) noexcept { if (p) g_live -= malloc_usable_size(p); free(p); }
void operator delete[](void* p, size_t) noexcept { if (p) g_live -= malloc_usable_size(p); free(p); }
static size_t heapNow() { return g_live; }
static const char* heapSource() { return "operator new only"; }
#endif
static size_t g_peak = 0;
static void samplePeak() { size_t h = heapNow(); if (h > g_peak) g_peak = h; }

// Transport that behaves like a real one: close() reports the close back to the core.
struct LiveTransport : public MemTransport {
  int failAfterFrames = -1;    // sendFrame fails from this frame on (-1 = never)
  bool closeOnFail = false;    // and reports the close synchronously, like a stream that sees EOF
  int frames = 0;
  bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) override {
    samplePeak();
    if (failAfterFrames >= 0 && frames++ >= failAfterFrames) {
      if (closeOnFail) { closeOnFail = false; core_->onClose(slot); }
      return false;
    }
    return MemTransport::sendFrame(slot, data, len, first, last);
  }
  void close(uint8_t slot) override { MemTransport::close(slot); core_->onClose(slot); }
};

struct MultiRig {
  MemStore store; LiveTransport tr; Core core;
  MultiRig(const char* pin = nullptr) {
    core.setId("a1b2c3").setVersion("1.0.0"); core.addTransport(&tr); core.begin("Test", &store);
    if (pin) core.setPin(pin, true);
  }
  int open() { return core.onOpen(&tr); }
  void msg(int slot, const char* json) { core.onMessage((uint8_t)slot, json, strlen(json)); }
  int connect(const char* tok = nullptr) {
    int s = open(); if (s < 0) return s;
    Str m = "{\"t\":\"hello\",\"v\":1,\"client\":\"app\""; if (tok) { m += ",\"tok\":\""; m += tok; m += "\""; } m += "}";
    msg(s, m.c_str()); return s;
  }
  Str auth(int slot, const char* pin) {
    Client* c = core.client((uint8_t)slot);
    char mac[65]; pinMac(pin, c->nonce, "a1b2c3", mac);
    Str m = "{\"t\":\"auth\",\"mac\":\""; m += mac; m += "\"}"; msg(slot, m.c_str());
    int i = tr.find("\"tok\"", (uint8_t)slot); return i < 0 ? Str("") : Str(tr.at((uint8_t)slot, i)["tok"].as<const char*>());
  }
  void flushAll() { for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) { Client* c = core.client(i); if (c->used) c->lastFlush -= 1000; } core.loop(); }
};

// Mirrors examples/FullDemo/FullDemo.ino (widgets and persist; the callbacks are stand-ins).
static void buildFullDemo(Ui& ui) {
  ui.page("main", "Boiler").icon("home");
  ui.header("Fake boiler");
  ui.group("sensors", "Sensors");
  ui.gauge("temp", "Temperature", 0, 120, "°C").style("round").zone(90, 120, "#ff0000").group("sensors");
  ui.chart("tchart", "Temp history", 600, "°C").series("temp", "Temp", "#ff8800").series("target", "Target", "#0088ff").group("sensors");
  ui.progress("level", "Tank").group("sensors");
  ui.progress("bal", "Balance", -100, 100).center().group("sensors");
  ui.display("disp", "Pressure", 5, "bar").group("sensors");
  ui.led("ok", "OK", "#00ff00").group("sensors");
  ui.led("rgb", "Status").rgb().group("sensors");
  ui.clock("now", "Device time", "HH:mm:ss").group("sensors");
  ui.label("state", "State").group("sensors");
  ui.group("control", "Control");
  ui.row("r1").group("control");
  ui.sw("pump", "Pump").labels("ON", "OFF").row("r1").size(1).group("control");
  ui.slider("target", "Target", 20, 90, 1, "°C").row("r1").size(3).group("control").persist();
  ui.number("cycles", "Cycles", 0, 10).spin().group("control").persist();
  ui.select("mode", "Mode", {"Off", "Auto", "Manual"}).style("seg").group("control").persist().onChange([](int) {});
  ui.row("r2").group("control");
  ui.button("reset", "Reset error").hint("Clears the error latch").icon("restart_alt").row("r2").group("control").onClick([] {});
  ui.button("erase", "Erase").color("#ff0000").row("r2").group("control").onClick([] {});
  ui.button("rename", "Rename").row("r2").group("control").onClick([] {});
  ui.button("alert", "Notify").icon("warning").group("control").onClick([] {});
  ui.button("horn", "Horn").hold().color("#ff8800").group("control").onEvent([](int) {});
  ui.log("term", "Log", 200, 8);
  ui.page("io", "I/O").icon("tune");
  ui.group("inputs", "Inputs");
  ui.joystick("joy", "Valve").center().square().group("inputs").onMove([](int, int) {});
  ui.dpad("pad", "Move").group("inputs").onEvent([](int) {});
  ui.color("col", "Light").group("inputs").persist().onChange([](uint32_t) {});
  ui.datetime("start", "Start", "time").group("inputs").persist();
  ui.flags("days", "Days", {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}).group("inputs").persist();
  ui.table("tbl", "Zones").column("Zone", 2).column("°C", 1, "right");
  ui.image("img", "Diagram", "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/240px-PNG_transparency_demonstration_1.png");
  ui.stream("cam", "Camera", "http://192.168.1.60:81/stream");
  ui.map("pos", "Location", 14);
  ui.page("setup", "Setup").icon("settings");
  ui.textblock("help", "Set the target and enable the pump.\nThe horn button is momentary.");
  ui.text("name", "Name", 32).regex("^[A-Za-z ]*$").persist();
  ui.text("pw", "Password", 64).secret();
  ui.textarea("notes", "Notes", 512, 4).persist();
  ui.spacer("sp", 1, 16);
  ui.button("reboot", "Reboot").color("#ff0000").onClick([] {});
}

static void buildMinimal(Ui& ui) {
  ui.gauge("temp", "Temperature", 0, 100, "°C");
  ui.sw("led", "LED").onChange([](bool) {});
}

void test_multi_client_pages_dirty_masks_and_set_echo() {
  MultiRig r; buildDemo(r.core.ui());
  int s[4]; for (int i = 0; i < 4; i++) { s[i] = r.connect(); TEST_ASSERT_EQUAL(i, s[i]); }
  TEST_ASSERT_EQUAL(4, r.core.clients());
  TEST_ASSERT_EQUAL(-1, r.open());                              // no fifth slot
  r.msg(s[1], "{\"t\":\"page\",\"id\":\"setup\"}");             // client 1 looks at another page
  r.tr.clear();
  r.msg(s[2], "{\"t\":\"set\",\"id\":\"target\",\"v\":50}");
  TEST_ASSERT_EQUAL(0, r.tr.count(2));                         // no immediate echo, no error
  // flush only client 0: the others keep their dirty bits
  for (uint8_t i = 1; i < 4; i++) r.core.client(i)->lastFlush = nowMs();
  r.core.client(0)->lastFlush -= 1000; r.core.loop();
  TEST_ASSERT_EQUAL(1, r.tr.count(0)); TEST_ASSERT_EQUAL(50, r.tr.last(0)["v"]["target"].as<int>());
  TEST_ASSERT_EQUAL(0, r.tr.count(2)); TEST_ASSERT_EQUAL(0, r.tr.count(3));
  r.flushAll();
  TEST_ASSERT_EQUAL(1, r.tr.count(0));                         // already flushed, nothing new
  TEST_ASSERT_EQUAL(50, r.tr.last(2)["v"]["target"].as<int>());   // the sender gets its own echo (PROTOCOL 4.5)
  TEST_ASSERT_EQUAL(50, r.tr.last(3)["v"]["target"].as<int>());
  TEST_ASSERT_EQUAL(0, r.tr.count(1));                         // other page: nothing
  r.msg(s[1], "{\"t\":\"page\",\"id\":\"main\"}");
  TEST_ASSERT_EQUAL(50, r.tr.last(1)["v"]["target"].as<int>());   // full upd of the page carries it
  // a rejected set re-sends the current value to the sender only
  r.tr.clear();
  r.msg(s[3], "{\"t\":\"set\",\"id\":\"target\",\"v\":500}");
  TEST_ASSERT_EQUAL(7, r.tr.last(3)["code"].as<int>());
  r.flushAll();
  TEST_ASSERT_EQUAL(2, r.tr.count(3)); TEST_ASSERT_EQUAL(50, r.tr.last(3)["v"]["target"].as<int>());
  for (int i = 0; i < 3; i++) TEST_ASSERT_EQUAL(0, r.tr.count(i));
  // a sketch set reaches every client on the page
  r.core.ui().set("temp", 77.f); r.flushAll();
  for (int i = 0; i < 4; i++) TEST_ASSERT_EQUAL(77, r.tr.last(i)["v"]["temp"].as<int>());
  // disconnect in the middle, the slot is reused, the others are untouched
  r.core.onClose((uint8_t)s[1]);
  TEST_ASSERT_EQUAL(3, r.core.clients());
  TEST_ASSERT_EQUAL(1, r.connect());
  TEST_ASSERT_EQUAL(77, r.tr.at(1, r.tr.count(1) - 1)["v"]["temp"].as<int>());
  TEST_ASSERT_EQUAL(4, r.core.clients());
}

void test_fifth_client_across_two_transports_and_revoke() {
  MultiRig r("1234"); r.core.ui().sw("a", "A");
  FakeStream io; StreamTransport st(io, "serial"); r.core.addTransport(&st);
  // three WS-like clients plus one stream client
  Str tok;
  for (int i = 0; i < 3; i++) { int s = r.connect(tok.length() ? tok.c_str() : nullptr); if (!tok.length()) tok = r.auth(s, "1234"); }
  TEST_ASSERT_EQUAL(32, tok.length());
  Str h = "{\"t\":\"hello\",\"v\":1,\"client\":\"app\",\"tok\":\""; h += tok; h += "\"}\n"; io.push(h.c_str()); r.core.loop();
  TEST_ASSERT_TRUE(st.open()); TEST_ASSERT_EQUAL(4, r.core.clients());
  // the fifth: no slot on the WS side, err 9 on a second stream
  TEST_ASSERT_EQUAL(-1, r.open());
  FakeStream io2; StreamTransport st2(io2, "uart"); r.core.addTransport(&st2);
  io2.push("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n"); r.core.loop();
  TEST_ASSERT_FALSE(st2.open()); TEST_ASSERT_EQUAL(9, io2.last()["code"].as<int>());
  // revoke from the stream client drops the three others and the token
  io.push("{\"t\":\"sys\",\"cmd\":\"revoke\"}\n"); r.core.loop();
  TEST_ASSERT_TRUE(io.last()["ok"].as<bool>());
  TEST_ASSERT_EQUAL(3, r.tr.closed.size());
  TEST_ASSERT_EQUAL(1, r.core.clients()); TEST_ASSERT_TRUE(st.open());
  TEST_ASSERT_FALSE(r.core.auth().validToken(tok.c_str()));
  int s = r.connect(tok.c_str());
  TEST_ASSERT_FALSE(r.tr.at((uint8_t)s, 0)["ok"].as<bool>());
  // the freed slots take the second stream now
  io2.push("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n"); r.core.loop();
  TEST_ASSERT_TRUE(st2.open());
}

void test_unauthenticated_client_timeout() {
  MultiRig r("1234"); r.core.ui().sw("a", "A");
  int idle = r.open();                                  // never speaks
  int halfway = r.connect();                            // hello, never auth
  int ok = r.connect(); Str tok = r.auth(ok, "1234"); TEST_ASSERT_EQUAL(32, tok.length());
  r.core.loop();
  TEST_ASSERT_EQUAL(0, r.tr.closed.size());
  r.core.client((uint8_t)idle)->connectedAt -= ESPFACE_AUTH_TIMEOUT_MS;
  r.core.client((uint8_t)halfway)->connectedAt -= ESPFACE_AUTH_TIMEOUT_MS;
  r.core.client((uint8_t)ok)->connectedAt -= ESPFACE_AUTH_TIMEOUT_MS;
  r.core.loop();
  TEST_ASSERT_EQUAL(2, r.tr.closed.size());
  TEST_ASSERT_EQUAL(3, r.tr.last((uint8_t)halfway)["code"].as<int>());
  TEST_ASSERT_EQUAL_STRING("auth timeout", r.tr.last((uint8_t)idle)["msg"]);
  TEST_ASSERT_FALSE(r.core.client((uint8_t)idle)->used);
  TEST_ASSERT_TRUE(r.core.client((uint8_t)ok)->authed);
  TEST_ASSERT_EQUAL(1, r.core.clients());
  // same on a stream: the transport closes the session on the next loop
  StreamRig s("1234"); s.send("{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}\n");
  TEST_ASSERT_TRUE(s.tr.open());
  s.core.client((uint8_t)s.tr.slot())->connectedAt -= ESPFACE_AUTH_TIMEOUT_MS;
  s.core.loop(); s.core.loop();
  TEST_ASSERT_FALSE(s.tr.open());
  TEST_ASSERT_EQUAL(3, s.io.last()["code"].as<int>());
}

void test_token_reuse_from_two_clients_at_once() {
  MultiRig r("1234"); r.core.ui().sw("a", "A");
  int a = r.connect(); Str tok = r.auth(a, "1234");
  int b = r.connect(tok.c_str()); int c = r.connect(tok.c_str());
  TEST_ASSERT_TRUE(r.tr.at((uint8_t)b, 0)["ok"].as<bool>()); TEST_ASSERT_TRUE(r.tr.at((uint8_t)c, 0)["ok"].as<bool>());
  TEST_ASSERT_EQUAL_STRING("ui", r.tr.at((uint8_t)c, 1)["t"]);
  TEST_ASSERT_EQUAL(3, r.core.clients());
  // a wrong token is a fresh pairing, not a lockout hit
  int d = r.connect("00000000000000000000000000000000");
  TEST_ASSERT_FALSE(r.tr.at((uint8_t)d, 0)["ok"].as<bool>()); TEST_ASSERT_EQUAL(32, strlen(r.tr.at((uint8_t)d, 0)["nonce"] | ""));
  // pin.set from one client clears tokens but keeps the live sessions
  r.msg(b, "{\"t\":\"sys\",\"cmd\":\"pin.set\",\"pin\":\"5678\"}");
  TEST_ASSERT_TRUE(r.tr.last((uint8_t)b)["ok"].as<bool>());
  TEST_ASSERT_EQUAL(3, r.core.clients()); TEST_ASSERT_EQUAL(0, r.tr.closed.size());
  r.core.onClose((uint8_t)d); r.tr.clear();
  int e = r.connect(tok.c_str());
  TEST_ASSERT_FALSE(r.tr.at((uint8_t)e, 0)["ok"].as<bool>());
  TEST_ASSERT_EQUAL(32, r.auth(e, "5678").length());
}

void test_dialog_any_client_answers_late_joiner_other_ui() {
  MultiRig r; buildDemo(r.core.ui());
  int a = r.connect(), b = r.connect(); r.tr.clear();
  int answers = 0; bool okSeen = false;
  r.core.ui().confirm("d1", "Erase?", [&](bool ok, const Str&) { answers++; okSeen = ok; });
  TEST_ASSERT_EQUAL_STRING("dlg", r.tr.last((uint8_t)a)["t"]); TEST_ASSERT_EQUAL_STRING("dlg", r.tr.last((uint8_t)b)["t"]);
  TEST_ASSERT_EQUAL(60, r.tr.last((uint8_t)a)["timeout"].as<int>());
  r.msg(b, "{\"t\":\"dlg\",\"id\":\"d1\",\"ok\":true}");       // rule: any authenticated client of the UI may answer, first wins
  TEST_ASSERT_EQUAL(1, answers); TEST_ASSERT_TRUE(okSeen);
  TEST_ASSERT_TRUE(r.tr.last((uint8_t)a)["close"].as<bool>()); TEST_ASSERT_TRUE(r.tr.last((uint8_t)b)["close"].as<bool>());
  r.msg(a, "{\"t\":\"dlg\",\"id\":\"d1\",\"ok\":false}");
  TEST_ASSERT_EQUAL(6, r.tr.last((uint8_t)a)["code"].as<int>()); TEST_ASSERT_EQUAL(1, answers);
  // a client that joins while a dialog is open receives it after ui/upd, with the remaining timeout
  Str text;
  r.core.ui().prompt("d2", "Name?", [&](bool, const Str& v) { text = v; }, "x", "Rename", 30);
  int c = r.connect();
  int di = r.tr.find("\"t\":\"dlg\"", (uint8_t)c);
  TEST_ASSERT_TRUE(di >= 3);
  JsonDocument d = r.tr.at((uint8_t)c, di);
  TEST_ASSERT_EQUAL_STRING("d2", d["id"]); TEST_ASSERT_EQUAL_STRING("prompt", d["kind"]); TEST_ASSERT_EQUAL_STRING("x", d["def"]);
  TEST_ASSERT_EQUAL_STRING("Rename", d["title"]); TEST_ASSERT_TRUE(d["timeout"].as<int>() >= 29 && d["timeout"].as<int>() <= 30);
  r.msg(c, "{\"t\":\"dlg\",\"id\":\"d2\",\"ok\":true,\"v\":\"Kitchen\"}");
  TEST_ASSERT_EQUAL_STRING("Kitchen", text.c_str());
  TEST_ASSERT_EQUAL(0, r.core.ui().dialogs().size());
  // a client on another UI neither sees nor can answer the dialog
  Ui& setup = r.core.addUi("setup"); setup.text("ssid", "SSID");
  LiveTransport tr2; r.core.addTransport(&tr2); tr2.use(setup);
  int s = r.core.onOpen(&tr2); r.core.onMessage((uint8_t)s, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  r.core.ui().confirm("d3", "Main only", [&](bool, const Str&) { answers++; });
  TEST_ASSERT_EQUAL(-1, tr2.find("\"t\":\"dlg\"", (uint8_t)s));
  r.core.onMessage((uint8_t)s, "{\"t\":\"dlg\",\"id\":\"d3\",\"ok\":true}", 32);
  TEST_ASSERT_EQUAL(6, tr2.last((uint8_t)s)["code"].as<int>()); TEST_ASSERT_EQUAL(1, answers);
  TEST_ASSERT_EQUAL(1, r.core.ui().dialogs().size());
}

void test_client_disconnects_mid_ui_stream() {
  MultiRig r; buildDemo(r.core.ui());
  int connects = 0, disconnects = 0;
  r.core.onConnect([&](const ClientInfo&) { connects++; });
  r.core.onDisconnect([&](const ClientInfo&) { disconnects++; });
  // the transport reports the close synchronously while the ui message streams out
  r.tr.failAfterFrames = 2; r.tr.closeOnFail = true;
  int s = r.connect();
  TEST_ASSERT_FALSE(r.core.client((uint8_t)s)->used);
  TEST_ASSERT_EQUAL(0, r.core.clients()); TEST_ASSERT_EQUAL(0, connects); TEST_ASSERT_EQUAL(0, disconnects);
  TEST_ASSERT_EQUAL(1, r.tr.count((uint8_t)s));            // only the hello went out
  // a WebSocket-like transport just fails the frames, the close event comes later
  r.tr.failAfterFrames = 2; r.tr.closeOnFail = false; r.tr.frames = 0; r.tr.clear();
  int s2 = r.connect();
  TEST_ASSERT_TRUE(r.core.client((uint8_t)s2)->authed);
  TEST_ASSERT_EQUAL(1, connects);
  TEST_ASSERT_TRUE(r.tr.frames <= 5);                       // the rest of the ui and the upd were not even attempted
  r.core.ui().set("temp", 1.f); r.flushAll();
  r.core.onClose((uint8_t)s2);
  TEST_ASSERT_EQUAL(1, disconnects);
  // and the next client is served in full
  r.tr.failAfterFrames = -1; r.tr.clear();
  int s3 = r.connect();
  TEST_ASSERT_EQUAL_STRING("upd", r.tr.at((uint8_t)s3, 2)["t"]);
  TEST_ASSERT_EQUAL(22, r.tr.at((uint8_t)s3, 1)["w"].size());
  TEST_ASSERT_EQUAL(2, connects);
}

// ---- fuzz and soak -----------------------------------------------------------------------
static uint32_t g_rnd = 0x9e3779b9u;
static uint32_t rnd() { g_rnd ^= g_rnd << 13; g_rnd ^= g_rnd >> 17; g_rnd ^= g_rnd << 5; return g_rnd; }

static std::vector<Str> loadC2dVectors() {
  std::vector<Str> out;
  DIR* d = opendir("../protocol/vectors");
  if (!d) return out;
  std::vector<Str> files;
  while (dirent* e = readdir(d)) { Str n = e->d_name; if (n.size() > 5 && n.compare(n.size() - 5, 5, ".json") == 0) files.push_back(n); }
  closedir(d);
  std::sort(files.begin(), files.end());
  for (auto& f : files) {
    Str path = "../protocol/vectors/" + f;
    FILE* fp = fopen(path.c_str(), "rb"); if (!fp) continue;
    Str raw; char buf[4096]; size_t n; while ((n = fread(buf, 1, sizeof buf, fp)) > 0) raw.append(buf, n); fclose(fp);
    JsonDocument doc; if (deserializeJson(doc, raw)) continue;
    for (JsonObject v : doc.as<JsonArray>()) {
      if (strcmp(v["dir"] | "", "c2d")) continue;
      Str m; serializeJson(v["msg"], m); out.push_back(m);
    }
  }
  return out;
}

struct FuzzRig : public MultiRig {
  Str tok;
  FuzzRig() : MultiRig("1234") {
    buildFullDemo(core.ui()); core.addCap("ota"); core.addCap("otaurl"); core.addCap("wifi");
    core.sysHook = [](uint8_t, const char*, void*) { return false; };
    core.binaryHook = [](uint8_t, const uint8_t*, size_t) { return false; };
  }
  // slot 0 authed, slot 1 hello only, slot 2 nothing yet, slot 3 authed via token
  void prime() {
    for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) if (core.client(i)->used) core.onClose(i);
    tr.clear(); tr.closed.clear();
    core.setPin("", true); connect();                       // authed without a PIN (fuzzed auth may have locked the PIN)
    core.setPin("1234", true); connect(); open();           // hello only; silent
    core.setPin("", true); connect(); core.setPin("1234", true);
  }
  void feed(const Str& m) { for (uint8_t s = 0; s < ESPFACE_MAX_CLIENTS; s++) if (core.client(s)->used) core.onMessage(s, m.c_str(), m.length()); }
  void feedBin(const uint8_t* p, size_t n) { for (uint8_t s = 0; s < ESPFACE_MAX_CLIENTS; s++) if (core.client(s)->used) core.onBinary(s, p, n); }
  bool alive() {   // the core still serves a fresh client correctly
    for (uint8_t i = 0; i < ESPFACE_MAX_CLIENTS; i++) if (core.client(i)->used) core.onClose(i);
    tr.clear(); core.setPin("", true); int s = connect(); if (s < 0) return false;
    if (strcmp(tr.at((uint8_t)s, 0)["t"] | "", "hello") || !(tr.at((uint8_t)s, 0)["ok"] | false)) return false;
    if (strcmp(tr.at((uint8_t)s, 1)["t"] | "", "ui") || strcmp(tr.at((uint8_t)s, 2)["t"] | "", "upd")) return false;
    int n = tr.count((uint8_t)s); msg(s, "{\"t\":\"set\",\"id\":\"pump\",\"v\":true}");
    return tr.count((uint8_t)s) == n && core.ui().get("pump")->asBool();
  }
};

void test_fuzz_vectors_mutations_garbage_no_crash_no_leak() {
  std::vector<Str> vec = loadC2dVectors();
  TEST_ASSERT_TRUE_MESSAGE(vec.size() >= 20, "protocol/vectors not found (run from firmware/)");
  FILE* keep = g_out; g_out = nullptr;
  FuzzRig r; r.prime();
  const int rounds = 40;
  size_t baseline = 0; int msgs = 0;
  for (int round = 0; round < rounds; round++) {
    for (auto& m : vec) {
      r.feed(m); msgs++;
      for (size_t cut = 1; cut < m.length(); cut += 1 + (rnd() % 5)) { Str t = m.substr(0, cut); r.feed(t); msgs++; }   // truncated
      for (int k = 0; k < 6; k++) { Str t = m; t[rnd() % t.length()] = (char)(rnd() & 0xff); r.feed(t); msgs++; }   // bit rot
      { Str t = m; t.insert(t.length() - 1, ",\"pad\":\""); t.append(ESPFACE_MAX_MSG + 100, 'x'); t += "\"}"; r.feed(t); msgs++; }   // oversized
      { Str t = m; t.insert(t.length() - 1, ",\"x\":" + Str(600, '[') + Str(600, ']')); r.feed(t); msgs++; }                        // nested
      { Str t = "{\"t\":\"set\",\"id\":\"target\",\"v\":"; for (int d = 0; d < 300; d++) t += "{\"a\":"; t += "1"; r.feed(t); msgs++; }
    }
    for (int k = 0; k < 30; k++) {                                                                   // random bytes, text and binary
      size_t n = rnd() % 300; Str t; for (size_t i = 0; i < n; i++) t += (char)(rnd() & 0xff);
      r.feed(t); r.feedBin((const uint8_t*)t.data(), t.length()); msgs += 2;
      static const char* frag[] = {"{", "}", "[", "\"t\":", "\"hello\"", "\"set\"", "\"sys\"", "\"cmd\":", "\"id\":", "\"v\":", "1e400", "-0", "null", "true", ",", ":", "\\u0000", "\"\\\"", "\"ota.begin\"", "\"dlg\"", "\"page\""};
      Str f; int parts = 1 + rnd() % 12; for (int i = 0; i < parts; i++) f += frag[rnd() % (sizeof frag / sizeof *frag)];
      r.feed(f); msgs++;
    }
    r.flushAll(); r.core.loop();
    if (!r.alive()) TEST_FAIL_MESSAGE("core stopped answering after fuzz round");
    r.prime();
    if (round == 12) baseline = heapNow();   // after the token ring (8) and the store are full
  }
  r.prime(); r.core.loop();
  size_t end = heapNow();
  g_out = keep;
  printf("[fuzz] %d messages over %d rounds, heap after warm-up %zu bytes, at end %zu bytes (%s)\n", msgs, rounds, baseline, end, heapSource());
  TEST_ASSERT_TRUE_MESSAGE(end <= baseline + 64, "heap grew during fuzz");
  TEST_ASSERT_TRUE(r.alive());
}

void test_ram_soak_connect_cycles() {
  FILE* keep = g_out; g_out = nullptr;
  MultiRig r("1234"); buildFullDemo(r.core.ui());
  r.core.onConnect([](const ClientInfo&) {}); r.core.onDisconnect([](const ClientInfo&) {});
  const int cycles = 10000;
  size_t baseline = 0, peakSeen = 0; Str tok;
  for (int i = 0; i < cycles; i++) {
    int s = r.connect(tok.length() && (i % 3) ? tok.c_str() : nullptr);
    if (s < 0) TEST_FAIL_MESSAGE("no free slot");
    if (!r.core.client((uint8_t)s)->authed) tok = r.auth(s, "1234");
    if (!r.core.client((uint8_t)s)->authed) TEST_FAIL_MESSAGE("auth failed");
    char m[96]; snprintf(m, sizeof m, "{\"t\":\"set\",\"id\":\"target\",\"v\":%d}", 20 + i % 70); r.msg(s, m);
    if (i % 2) r.msg(s, "{\"t\":\"page\",\"id\":\"io\"}");
    r.msg(s, "{\"t\":\"sys\",\"cmd\":\"info\"}");
    r.core.ui().set("temp", (float)(i % 120)); r.core.ui().logLine("term", "tick"); r.core.ui().push("tchart", "temp", 1.f);
    r.flushAll();
    if (i % 4 == 3) { for (uint8_t k = 0; k < ESPFACE_MAX_CLIENTS; k++) if (r.core.client(k)->used) r.core.onClose(k); r.tr.clear(); }   // up to 4 at a time
    if (i == 99) baseline = heapNow();
    if (i > 99 && heapNow() > peakSeen) peakSeen = heapNow();
  }
  for (uint8_t k = 0; k < ESPFACE_MAX_CLIENTS; k++) if (r.core.client(k)->used) r.core.onClose(k);
  r.tr.clear(); r.core.loop();
  size_t end = heapNow();
  g_out = keep;
  printf("[soak] %d connect/auth/ui/set/upd/disconnect cycles, heap after 100 cycles %zu bytes, at end %zu bytes, peak %zu (%s)\n", cycles, baseline, end, peakSeen, heapSource());
  TEST_ASSERT_TRUE_MESSAGE(end <= baseline, "heap grew during the soak");
}

static size_t measureUi(const char* label, void (*build)(Ui&)) {
  FILE* keep = g_out; g_out = nullptr;
  size_t before = heapNow();
  MemStore* store = new MemStore; LiveTransport* tr = new LiveTransport; Core* core = new Core;
  core->setId("a1b2c3"); core->addTransport(tr); core->begin("Measure", store); core->setPin("1234", true);
  build(core->ui());
  size_t built = heapNow();
  g_peak = built;
  int s = core->onOpen(tr); core->onMessage((uint8_t)s, "{\"t\":\"hello\",\"v\":1,\"client\":\"app\"}", 36);
  Client* c = core->client((uint8_t)s);
  { char mac[65]; pinMac("1234", c->nonce, "a1b2c3", mac); Str a = "{\"t\":\"auth\",\"mac\":\""; a += mac; a += "\"}"; core->onMessage((uint8_t)s, a.c_str(), a.length()); }
  size_t uiBytes = 0; for (auto& m : tr->msgs[s]) uiBytes += m.length();
  tr->clear();
  core->ui().set("temp", 42.f); c->lastFlush -= 1000; core->loop();
  core->onMessage((uint8_t)s, "{\"t\":\"set\",\"id\":\"led\",\"v\":true}", 31);
  core->onMessage((uint8_t)s, "{\"t\":\"set\",\"id\":\"target\",\"v\":30}", 33);
  core->onMessage((uint8_t)s, "{\"t\":\"sys\",\"cmd\":\"info\"}", 25);
  c->lastFlush -= 1000; core->loop();
  size_t peak = g_peak; tr->clear(); core->loop();
  size_t steady = heapNow(), widgets = core->ui().count();
  delete core; delete tr; delete store;
  size_t after = heapNow();
  g_out = keep;
  printf("[heap] %-8s widgets %2zu: library objects %zu B (core+ui+transport, before clients), hello traffic %zu B, "
         "steady with 1 client %zu B, peak while serving %zu B (sampled at frame boundaries); sizeof Core %zu Client %zu Widget %zu Value %zu (%s)\n",
         label, widgets, built - before, uiBytes, steady - before, peak - before, sizeof(Core), sizeof(Client), sizeof(Widget), sizeof(Value), heapSource());
  if (after > before + 64) printf("[heap] %s: %zu bytes retained after teardown\n", label, after - before);
  return after > before + 64 ? after - before : 0;
}


void test_heap_steady_state_report() {
  measureUi("warm-up", buildMinimal);          // one-time lazy allocations (stdio, locale) settle here
  TEST_ASSERT_EQUAL(0, measureUi("Minimal", buildMinimal));
  TEST_ASSERT_EQUAL(0, measureUi("FullDemo", buildFullDemo));
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
  RUN_TEST(test_caps_gating);
  RUN_TEST(test_ota_push_state_machine);
  RUN_TEST(test_ota_url);
  RUN_TEST(test_reset_reason_mapping);
  RUN_TEST(test_info_fields);
  RUN_TEST(test_ntfy_rate_limit);
  RUN_TEST(test_line_framer);
  RUN_TEST(test_ble_framer_roundtrip_and_mtu);
  RUN_TEST(test_ble_framer_gap_duplicate_oversize);
  RUN_TEST(test_stream_transport_end_to_end);
  RUN_TEST(test_ota_begin_refused_on_stream);
  RUN_TEST(test_multi_client_pages_dirty_masks_and_set_echo);
  RUN_TEST(test_fifth_client_across_two_transports_and_revoke);
  RUN_TEST(test_unauthenticated_client_timeout);
  RUN_TEST(test_token_reuse_from_two_clients_at_once);
  RUN_TEST(test_dialog_any_client_answers_late_joiner_other_ui);
  RUN_TEST(test_client_disconnects_mid_ui_stream);
  RUN_TEST(test_fuzz_vectors_mutations_garbage_no_crash_no_leak);
  RUN_TEST(test_ram_soak_connect_cycles);
  RUN_TEST(test_heap_steady_state_report);
  if (g_out) fclose(g_out);
  return UNITY_END();
}
