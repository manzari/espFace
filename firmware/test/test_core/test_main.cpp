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
  if (g_out) fclose(g_out);
  return UNITY_END();
}
