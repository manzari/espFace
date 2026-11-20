import { test, type Browser } from "@playwright/test";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Landing page screenshots of the renderer in a desktop browser (scripts/promo-shots.sh), against a mocked device.
// The UI and its values mirror the app's store screenshots (apps/mobile/test/screenshots_test.dart).
const OUT = fileURLToPath(new URL("../../promo/images", import.meta.url));
const T0 = Date.UTC(2026, 9, 1, 9, 30);
const NOW = T0 + 600000;
// 1000x625 CSS pixels at 1.4 gives the 1400x875 the landing page engine expects.
const VIEW = { width: 1000, height: 625 };
const SCALE = 1.4;

const UI = [
  { id: "main", ty: "page", lbl: "Boiler", icon: "home" },
  { id: "io", ty: "page", lbl: "I/O", icon: "tune" },
  { id: "setup", ty: "page", lbl: "Setup", icon: "settings" },
  { id: "sensors", ty: "group", lbl: "Sensors" },
  { id: "temp", ty: "gauge", lbl: "Temperature", min: 0, max: 120, unit: "°C", style: "round", zones: [{ from: 90, to: 120, color: "#ff0000" }], grp: "sensors", ro: true },
  { id: "tchart", ty: "chart", lbl: "Temp history", series: [{ id: "temp", lbl: "Temp", color: "#ff8800" }, { id: "target", lbl: "Target", color: "#0088ff" }], win: 600, unit: "°C", legend: true, vals: true, grp: "sensors" },
  { id: "level", ty: "progress", lbl: "Tank", min: 0, max: 100, grp: "sensors" },
  { id: "disp", ty: "display", lbl: "Pressure", digits: 5, unit: "bar", grp: "sensors" },
  { id: "ok", ty: "led", lbl: "Burner", color: "#00c853", grp: "sensors" },
  { id: "control", ty: "group", lbl: "Control" },
  { id: "r1", ty: "row", grp: "control" },
  { id: "pump", ty: "switch", lbl: "Pump", on: "ON", off: "OFF", row: "r1", size: 2, grp: "control" },
  { id: "target", ty: "slider", lbl: "Target", min: 20, max: 90, step: 1, unit: "°C", row: "r1", size: 3, grp: "control" },
  { id: "mode", ty: "select", lbl: "Mode", opts: ["Off", "Auto", "Manual"], style: "seg", grp: "control" },
  { id: "n", ty: "number", lbl: "Cycles", min: 0, max: 10, step: 1, spin: true, grp: "control" },
  { id: "reset", ty: "button", lbl: "Reset error", hint: "Clears the error latch", icon: "restart_alt", grp: "control" },
  { id: "term", ty: "log", lbl: "Log", rows: 6, cap: 200 },
  { id: "inputs", ty: "group", lbl: "Inputs", page: "io" },
  { id: "joy", ty: "joystick", lbl: "Valve", center: true, sq: true, grp: "inputs", page: "io" },
  { id: "col", ty: "color", lbl: "Light", grp: "inputs", page: "io" },
  { id: "start", ty: "datetime", lbl: "Start", mode: "time", grp: "inputs", page: "io" },
  { id: "days", ty: "flags", lbl: "Days", opts: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], grp: "inputs", page: "io" },
  { id: "tbl", ty: "table", lbl: "Zones", cols: [{ lbl: "Zone", w: 2, align: "left" }, { lbl: "°C", w: 1, align: "right" }], page: "io" },
  { id: "help", ty: "textblock", text: "Set the target and enable the pump.", page: "setup" },
  { id: "name", ty: "text", lbl: "Name", maxlen: 32, page: "setup" },
];

const VALUES = {
  temp: 61.1, level: 70, disp: 1.85, ok: true, pump: true, target: 65, mode: 1, n: 3,
  joy: [0, 0], col: 0xff8800, start: 6 * 3600, days: 31,
  tbl: [["Kitchen", 21.5], ["Bath", 23.0], ["Hall", 19.8]], name: "Boiler",
};

const PUSH = [
  { t: "pts", id: "tchart", s: "temp", p: Array.from({ length: 60 }, (_, i) => [T0 + i * 10000, Math.round((48 + 16 * (1 - 1 / (1 + i / 10)) + 0.6 * Math.sin(i / 2.5)) * 10) / 10]) },
  { t: "pts", id: "tchart", s: "target", p: Array.from({ length: 10 }, (_, k) => [T0 + k * 60000, k < 3 ? 60 : 65]) },
  ...["boot ok, fw 1.2.0", "wifi connected: Home (-61 dBm)", "burner on", "target 60 -> 65 °C"].map((msg, i) => ({ t: "log", id: "term", msg, ts: NOW - (4 - i) * 9000 })),
];

async function shoot(browser: Browser, name: string, scheme: "light" | "dark", top?: string) {
  const ctx = await browser.newContext({ viewport: VIEW, deviceScaleFactor: SCALE, colorScheme: scheme, timezoneId: "Europe/Berlin", locale: "en-GB" });
  try {
    const page = await ctx.newPage();
    await page.clock.setFixedTime(NOW);
    await page.routeWebSocket(/\/ws$/, (ws) => {
      ws.onMessage((raw) => {
        if (JSON.parse(String(raw)).t !== "hello") return;
        ws.send(JSON.stringify({ t: "hello", v: 1, name: "Boiler", id: "a1b2c3", fw: "1.2.0", auth: "none", ok: true, up: 3600000, caps: ["chart"] }));
        ws.send(JSON.stringify({ t: "ui", rev: 1, w: UI }));
        ws.send(JSON.stringify({ t: "upd", v: VALUES }));
        for (const m of PUSH) ws.send(JSON.stringify(m));
      });
    });
    await page.goto("/connect/?host=boiler.local");
    await page.locator('.w[data-id="term"]').waitFor();
    // Scrolls the card of this widget to just below the sticky header.
    if (top) await page.locator(`.w[data-id="${top}"]`).evaluate((el) => {
      (el.closest(".card") ?? el).scrollIntoView({ block: "start" });
      window.scrollBy(0, -72);
    });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(500);
    await page.mouse.move(0, 0);
    await page.screenshot({ path: `${OUT}/web-${name}-${scheme}.jpg`, quality: 88, animations: "disabled" });
  } finally {
    await ctx.close();
  }
}

// Native time inputs format by the browser process locale; the context locale does not reach them.
test.use({ launchOptions: { env: { ...process.env, LC_ALL: "en_GB.UTF-8" } } });

test.describe("promo screenshots", () => {
  test.describe.configure({ mode: "parallel" });
  test.skip(process.env.ESPFACE_PROMO_SHOTS !== "1", "set ESPFACE_PROMO_SHOTS=1 (scripts/promo-shots.sh)");
  test.beforeAll(() => { mkdirSync(OUT, { recursive: true }); });
  for (const scheme of ["light", "dark"] as const) {
    test(`device ${scheme}`, ({ browser }) => shoot(browser, "device", scheme));
    test(`controls ${scheme}`, ({ browser }) => shoot(browser, "controls", scheme, "pump"));
  }
});
