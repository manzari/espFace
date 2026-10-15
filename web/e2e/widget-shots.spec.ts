import { test, type Browser, type Page } from "@playwright/test";
import { mkdirSync } from "node:fs";

// Docs screenshots per widget type against a mocked device (scripts/widget-shots.sh); scenarios mirror docs/site/guide/widgets.md.
const OUT = process.env.ESPFACE_SHOTS_OUT ?? "../docs/site/public/widgets";
const NOW = Date.parse("2026-10-14T14:32:05+02:00");

type W = Record<string, unknown> & { id: string; ty: string };
type Scenario = {
  ty: string;
  w: W[];
  v?: Record<string, unknown>;
  push?: Record<string, unknown>[];
  ready?: (p: Page) => Promise<void>;
  page?: string;                  // click this bottom-nav entry, screenshot the whole viewport
  wait?: string;
  liveClock?: boolean;            // Leaflet's tile fade needs a running clock
  height?: number;
};

const svg = (body: string, w: number, h: number) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">${body}</svg>`;
const DIAGRAM = svg(`<rect width="360" height="200" fill="#f5f7fa"/>
<rect x="40" y="40" width="80" height="120" rx="10" fill="#ff8800" opacity=".85"/><text x="80" y="105" font-family="sans-serif" font-size="14" fill="#fff" text-anchor="middle">Boiler</text>
<path d="M120 70 H200 M120 130 H200" stroke="#2f7df6" stroke-width="6"/><circle cx="220" cy="70" r="20" fill="#2f7df6"/>
<text x="220" y="75" font-family="sans-serif" font-size="12" fill="#fff" text-anchor="middle">P</text>
<path d="M240 70 H300 V130 H200" stroke="#2f7df6" stroke-width="6" fill="none"/><rect x="290" y="90" width="40" height="30" rx="4" fill="#1f9d55"/>
<text x="310" y="145" font-family="sans-serif" font-size="11" fill="#555" text-anchor="middle">Radiator</text>`, 360, 200);
const CAMERA = svg(`<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5b7fa6"/><stop offset="1" stop-color="#a9c0d6"/></linearGradient></defs>
<rect width="400" height="240" fill="url(#s)"/><rect y="150" width="400" height="90" fill="#4c6b3c"/>
<rect x="60" y="90" width="110" height="80" fill="#c9b79c"/><path d="M50 95 L115 50 L180 95 Z" fill="#8c4a3a"/><rect x="100" y="125" width="30" height="45" fill="#5a4636"/>
<circle cx="320" cy="55" r="22" fill="#fff3b0"/><rect x="8" y="8" width="150" height="22" rx="4" fill="#000" opacity=".5"/>
<text x="16" y="24" font-family="monospace" font-size="13" fill="#fff">CAM 1  14:32:05</text>`, 400, 240);

function chartPoints(f: (i: number) => number) {
  const p: [number, number][] = [];
  for (let i = 0; i <= 120; i++) p.push([NOW - 600000 + i * 5000, Math.round(f(i) * 10) / 10]);
  return p;
}

const SCENARIOS: Scenario[] = [
  { ty: "label", w: [{ id: "state", ty: "label", lbl: "State" }], v: { state: "idle" } },
  { ty: "gauge", w: [{ id: "temp", ty: "gauge", lbl: "Temperature", min: 0, max: 120, unit: "°C", style: "round", zones: [{ from: 90, to: 120, color: "#ff0000" }] }], v: { temp: 42.5 } },
  { ty: "progress", w: [{ id: "bal", ty: "progress", lbl: "Balance", min: -100, max: 100, center: true }], v: { bal: 35 } },
  { ty: "display", w: [{ id: "disp", ty: "display", lbl: "Pressure", digits: 5, unit: "bar" }], v: { disp: 1.85 } },
  { ty: "led", w: [{ id: "ok", ty: "led", lbl: "OK", color: "#00ff00" }], v: { ok: true } },
  {
    ty: "chart",
    w: [{ id: "tchart", ty: "chart", lbl: "Temp history", win: 600, unit: "°C", style: "area", legend: true, vals: false,
      series: [{ id: "temp", lbl: "Temp", color: "#ff8800" }, { id: "target", lbl: "Target", color: "#0088ff" }] }],
    push: [
      { t: "pts", id: "tchart", s: "temp", p: chartPoints((i) => 48 + 14 * (1 - Math.exp(-i / 35)) + 0.8 * Math.sin(i / 4)) },
      { t: "pts", id: "tchart", s: "target", p: chartPoints((i) => (i < 30 ? 55 : 60)) },
    ],
    ready: (p) => drawn(p, "tchart", ["#ff8800", "#0088ff"]),
  },
  {
    ty: "log",
    w: [{ id: "term", ty: "log", lbl: "Log", cap: 200, rows: 8 }],
    push: [
      ["espFace 1.0.0 \"Boiler\" id a1b2c3", undefined], ["wifi connected 192.168.1.42", undefined], ["client app connected", undefined],
      ["pump on", undefined], ["target 65 °C", undefined], ["burner start", "#1f9d55"], ["temp 91.2 °C above limit", "#d9342b"], ["pump off", undefined],
    ].map(([msg, c], i) => ({ t: "log", id: "term", msg, ts: NOW - (8 - i) * 7000, ...(c ? { c } : {}) })),
  },
  {
    ty: "table",
    w: [{ id: "tbl", ty: "table", lbl: "Zones", cols: [{ lbl: "Zone", w: 2, align: "left" }, { lbl: "°C", w: 1, align: "right" }] }],
    v: { tbl: [["Kitchen", 21.5], ["Bath", 23.0], ["Hall", 19.8]] },
  },
  { ty: "image", w: [{ id: "img", ty: "image", lbl: "Diagram", src: "https://example.com/diagram.png" }], ready: (p) => imgLoaded(p, "img") },
  { ty: "stream", w: [{ id: "cam", ty: "stream", lbl: "Camera", src: "http://192.168.1.60:81/stream" }], ready: (p) => imgLoaded(p, "cam") },
  { ty: "clock", w: [{ id: "now", ty: "clock", lbl: "Device time", fmt: "HH:mm:ss" }], v: { now: Math.floor(NOW / 1000) } },
  {
    ty: "map",
    w: [{ id: "pos", ty: "map", lbl: "Location", zoom: 14 }],
    v: { pos: [[52.52, 13.405, "Boiler"]] },
    liveClock: true,
    ready: async (p) => {
      await p.locator(".leaflet-marker-icon").waitFor({ timeout: 30000 });
      await p.waitForFunction(() => { const t = document.querySelectorAll(".leaflet-tile"); return t.length > 0 && [...t].every((x) => x.classList.contains("leaflet-tile-loaded")); }, null, { timeout: 30000 });
      await p.waitForTimeout(800);
    },
  },
  { ty: "textblock", w: [{ id: "help", ty: "textblock", text: "Set the target and enable the pump." }] },
  { ty: "button", w: [{ id: "reset", ty: "button", lbl: "Reset error", icon: "restart_alt" }] },
  { ty: "switch", w: [{ id: "pump", ty: "switch", lbl: "Pump", on: "ON", off: "OFF" }], v: { pump: true } },
  { ty: "slider", w: [{ id: "target", ty: "slider", lbl: "Target", min: 20, max: 90, step: 1, unit: "°C" }], v: { target: 65 } },
  { ty: "number", w: [{ id: "cycles", ty: "number", lbl: "Cycles", min: 0, max: 10, step: 1, spin: true }], v: { cycles: 3 } },
  { ty: "text", w: [{ id: "name", ty: "text", lbl: "Name", maxlen: 32, re: "^[A-Za-z ]*$" }], v: { name: "Boiler" } },
  { ty: "textarea", w: [{ id: "notes", ty: "textarea", lbl: "Notes", maxlen: 512, rows: 4 }], v: { notes: "Serviced 2026-09-30.\nNext check in spring." } },
  { ty: "select", w: [{ id: "mode", ty: "select", lbl: "Mode", opts: ["Off", "Auto", "Manual"], style: "seg" }], v: { mode: 1 } },
  { ty: "flags", w: [{ id: "days", ty: "flags", lbl: "Days", opts: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] }], v: { days: 0b0011111 } },
  { ty: "color", w: [{ id: "col", ty: "color", lbl: "Light" }], v: { col: 0xff8800 } },
  { ty: "datetime", w: [{ id: "start", ty: "datetime", lbl: "Start", mode: "time" }], v: { start: 6 * 3600 + 30 * 60 } },
  { ty: "joystick", w: [{ id: "joy", ty: "joystick", lbl: "Valve", center: true, sq: true }], v: { joy: [0, 0] } },
  { ty: "dpad", w: [{ id: "pad", ty: "dpad", lbl: "Move" }] },
  { ty: "header", w: [{ id: "hdr", ty: "header", lbl: "Fake boiler" }] },
  {
    ty: "group",
    w: [{ id: "sensors", ty: "group", lbl: "Sensors", fold: true }, { id: "temp", ty: "gauge", lbl: "Temperature", min: 0, max: 120, unit: "°C", grp: "sensors" }],
    v: { temp: 42 },
  },
  {
    ty: "page",
    w: [
      { id: "main", ty: "page", lbl: "Boiler", icon: "home" }, { id: "io", ty: "page", lbl: "I/O", icon: "tune" }, { id: "setup", ty: "page", lbl: "Setup", icon: "settings" },
      { id: "temp", ty: "gauge", lbl: "Temperature", min: 0, max: 120, unit: "°C" },
      { id: "help", ty: "textblock", text: "Set the target and enable the pump.", page: "setup" },
      { id: "name", ty: "text", lbl: "Name", maxlen: 32, page: "setup" },
    ],
    v: { temp: 42, name: "Boiler" },
    page: "Setup",
    wait: "temp",
    height: 360,
  },
  {
    ty: "row",
    w: [
      { id: "control", ty: "group", lbl: "Control" }, { id: "r1", ty: "row", grp: "control" },
      { id: "pump", ty: "switch", lbl: "Pump", row: "r1", size: 2 },
      { id: "target", ty: "slider", lbl: "Target", min: 20, max: 90, step: 1, unit: "°C", row: "r1", size: 3 },
    ],
    v: { pump: true, target: 65 },
  },
  {
    ty: "spacer",
    w: [
      { id: "r1", ty: "row" },
      { id: "start", ty: "button", lbl: "Start", row: "r1" }, { id: "sp", ty: "spacer", size: [1, 16], row: "r1" }, { id: "stop", ty: "button", lbl: "Stop", row: "r1" },
    ],
  },
];

async function imgLoaded(p: Page, id: string) {
  await p.waitForFunction((i) => { const im = document.querySelector<HTMLImageElement>(`.w[data-id="${i}"] img`); return !!im && im.complete && im.naturalWidth > 0; }, id);
}

// Waits until every series color is on the chart canvas, so a screenshot never misses a series still being applied.
async function drawn(p: Page, id: string, colors: string[]) {
  await p.waitForFunction(([i, cs]) => {
    const c = document.querySelector<HTMLCanvasElement>(`.w[data-id="${i}"] canvas`);
    const d = c?.getContext("2d")?.getImageData(0, 0, c.width, c.height).data;
    if (!d) return false;
    return cs.every((h) => {
      const [r, g, b] = [1, 3, 5].map((k) => parseInt(h.slice(k, k + 2), 16));
      for (let j = 0; j < d.length; j += 4) if (Math.abs(d[j] - r) + Math.abs(d[j + 1] - g) + Math.abs(d[j + 2] - b) < 24) return true;
      return false;
    });
  }, [id, colors] as const);
}

async function shoot(browser: Browser, s: Scenario, scheme: "light" | "dark") {
  const ctx = await browser.newContext({
    viewport: { width: 400, height: s.height ?? 900 }, deviceScaleFactor: 2, colorScheme: scheme,
    timezoneId: "Europe/Berlin", locale: "en-GB", hasTouch: true,
  });
  try {
    const page = await ctx.newPage();
    if (!s.liveClock) await page.clock.setFixedTime(NOW);
    await page.route("https://example.com/diagram.png", (r) => r.fulfill({ contentType: "image/svg+xml", body: DIAGRAM }));
    await page.route("http://192.168.1.60:81/stream*", (r) => r.fulfill({ contentType: "image/svg+xml", body: CAMERA }));
    await page.routeWebSocket(/\/ws$/, (ws) => {
      ws.onMessage((raw) => {
        const m = JSON.parse(String(raw));
        if (m.t !== "hello") return;
        ws.send(JSON.stringify({ t: "hello", v: 1, name: "Boiler", id: "a1b2c3", fw: "1.0.0", auth: "none", ok: true, caps: ["chart"] }));
        ws.send(JSON.stringify({ t: "ui", rev: 1, w: s.w }));
        ws.send(JSON.stringify({ t: "upd", v: s.v ?? {} }));
        for (const x of s.push ?? []) ws.send(JSON.stringify(x));
      });
    });
    await page.goto("/connect/?host=shots.local");
    await page.locator(`.w[data-id="${s.wait ?? s.w[s.w.length - 1].id}"]`).first().waitFor();
    if (s.ready) await s.ready(page);
    await page.evaluate(() => document.fonts.ready);
    const file = `${OUT}/${s.ty}-${scheme}.png`;
    if (s.page) {
      await page.locator(".bottomnav button", { hasText: s.page }).click();
      await page.locator(`.w[data-id="${s.w[s.w.length - 1].id}"]`).waitFor();
      await page.screenshot({ path: file, animations: "disabled" });
    } else {
      const card = page.locator(".card").first();
      const box = (await card.boundingBox())!;
      const pad = 10;
      await page.mouse.move(0, 0);
      await page.screenshot({
        path: file, animations: "disabled",
        clip: { x: Math.max(0, box.x - pad), y: Math.max(0, box.y - pad), width: Math.min(400, box.width + 2 * pad), height: box.height + 2 * pad },
      });
    }
  } finally {
    await ctx.close();
  }
}

// Native time/date inputs format by the browser process locale; the context locale does not reach them.
test.use({ launchOptions: { env: { ...process.env, LC_ALL: "en_GB.UTF-8" } } });

test.describe("widget screenshots", () => {
  test.describe.configure({ mode: "parallel" });
  test.skip(process.env.ESPFACE_SHOTS !== "1", "set ESPFACE_SHOTS=1 (scripts/widget-shots.sh)");
  test.beforeAll(() => { mkdirSync(OUT, { recursive: true }); });
  for (const s of SCENARIOS) for (const scheme of ["light", "dark"] as const) test(`${s.ty} ${scheme}`, ({ browser }) => shoot(browser, s, scheme));
});
