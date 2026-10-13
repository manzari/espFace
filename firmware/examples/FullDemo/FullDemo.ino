// Every phase-1 feature: pages, groups, rows, all base widgets, persist, PIN, dialogs, props, log, chart, callbacks.
#include <espFace.h>

EspFace face;
float target = 60;
bool pump = false;
int cycles = 3;
bool hot = false;

void setup() {
  Serial.begin(115200);
  face.setProject("Home").setIcon("thermostat").setVersion("1.0.0").setRepo("manzari/espFace").setAbout("FullDemo boiler");
  face.begin("Boiler");
  face.setPin("1234");                     // comment out for an open device
  face.wifi().autoConnect();
  face.onConnect([](const ClientInfo& c) { Serial.printf("client %u connected via %s\n", c.slot, c.transport); });
  face.onDisconnect([](const ClientInfo& c) { Serial.printf("client %u left\n", c.slot); });
  face.onReboot([](RebootReason) { Serial.println("saving state before reboot"); });

  Ui& ui = face.ui();
  ui.page("main", "Boiler").icon("home");
  ui.header("Fake boiler");
  ui.group("sensors", "Sensors");
  ui.gauge("temp", "Temperature", 0, 120, "°C").style("round").zone(90, 120, "#ff0000").group("sensors");
  ui.chart("tchart", "Temp history", 600, "°C").series("temp", "Temp", "#ff8800").series("target", "Target", "#0088ff").group("sensors");
  ui.progress("level", "Tank").group("sensors");
  ui.led("ok", "OK", "#00ff00").group("sensors");
  ui.label("state", "State").group("sensors");

  ui.group("control", "Control");
  ui.row("r1").group("control");
  ui.sw("pump", "Pump").labels("ON", "OFF").row("r1").size(1).group("control").bind(pump);
  ui.slider("target", "Target", 20, 90, 1, "°C").row("r1").size(3).group("control").persist().bind(target);
  ui.number("cycles", "Cycles", 0, 10).spin().group("control").persist().bind(cycles);
  ui.select("mode", "Mode", {"Off", "Auto", "Manual"}).style("seg").group("control").persist()
      .onChange([](int m) { face.log("term", m == 0 ? "mode off" : m == 1 ? "mode auto" : "mode manual"); });
  ui.row("r2").group("control");
  ui.button("reset", "Reset error").hint("Clears the error latch").icon("restart_alt").row("r2").group("control")
      .onClick([] { face.set("ok", true); face.ui().prop("temp").color("#00ff00").label("Temperature"); face.toast("info", "Error cleared"); });
  ui.button("erase", "Erase").color("#ff0000").row("r2").group("control").onClick([] {
    face.ui().confirm("d1", "Erase all stored data?", [](bool ok, const Str&) {
      if (ok) { face.set("cycles", 0); face.toast("warn", "Erased"); } else face.toast("info", "Cancelled");
    }, "Erase");
  });
  ui.button("rename", "Rename").row("r2").group("control").onClick([] {
    face.ui().prompt("d2", "New state text", [](bool ok, const Str& v) { if (ok) face.set("state", v.c_str()); }, "idle");
  });
  ui.button("horn", "Horn").hold().color("#ff8800").group("control").onEvent([](int v) { face.log("term", v ? "horn pressed" : "horn released", "#ff8800"); });
  ui.log("term", "Log", 200, 8);

  ui.page("setup", "Setup").icon("settings");
  ui.textblock("help", "Set the target and enable the pump.\nThe horn button is momentary.");
  ui.text("name", "Name", 32).regex("^[A-Za-z ]*$").persist();
  ui.text("pw", "Password", 64).secret();
  ui.spacer("sp", 1, 16);
  ui.button("reboot", "Reboot").color("#ff0000").onClick([] { face.reboot(); });
}

void loop() {
  face.loop();
  static uint32_t last = 0, tick = 0;
  if (millis() - last >= 1000) {
    last = millis(); tick++;
    float temp = 60 + 30 * sinf(tick / 20.0f) + (pump ? 5 : 0);
    face.set("temp", temp);
    face.push("tchart", "temp", temp);
    face.push("tchart", "target", target);
    face.set("level", 50 + 40 * cosf(tick / 37.0f));
    if (tick % 5 == 0) face.log("term", pump ? "pump running" : "pump idle");
    if (temp > 85 && !hot) { hot = true; face.set("ok", false); face.ui().prop("temp").color("#ff0000").label("Temperature (HOT)"); face.toast("warn", "Overheating"); }
    if (temp < 80 && hot) { hot = false; face.ui().prop("temp").color("#00ff00").label("Temperature"); }
  }
}
