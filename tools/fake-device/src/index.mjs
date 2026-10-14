#!/usr/bin/env node
// espFace fake device: reference implementation of the device side of protocol v1 over WebSocket.
import { createServer } from "node:http";
import { randomBytes, createHmac, createHash, timingSafeEqual } from "node:crypto";
import { WebSocketServer } from "ws";
import { widgets as demoWidgets, initialValues, validValue, hugeUi } from "./demo-ui.mjs";

const PROTO_V = 1;
const FLUSH_MS = 100;
const LOCK_AFTER = 5;
const LOCK_SECONDS = 60;
const ERR = { json: 1, big: 2, unauth: 3, locked: 4, pin: 5, id: 6, value: 7, cap: 8, busy: 9, ota: 10 };

export class FakeDevice {
  constructor(opts = {}) {
    this.name = opts.name ?? "Fake boiler";
    this.id = opts.id ?? "a1b2c3";
    this.proj = opts.proj ?? "Demo";
    this.pin = opts.pin || null;
    this.maxClients = opts.maxClients ?? 4;
    this.logHistory = opts.logHistory ?? 20;
    this.simulate = opts.simulate ?? true;
    this.quiet = opts.quiet ?? false;
    // Hardening knobs (README): bad-network and limit simulation.
    this.dropEvery = opts.dropEvery ?? 0;        // close the socket after every N device->client messages
    this.latency = opts.latency ?? 0;            // ms added to every message in both directions
    this.slowUi = opts.slowUi ?? false;          // send `ui` as many small WebSocket fragments with delays
    this.flakyAuth = opts.flakyAuth ?? false;    // the first correct auth is answered with err 5 once
    this.fragmentSize = opts.fragmentSize ?? 512;
    this.fragmentDelay = opts.fragmentDelay ?? 20;
    const huge = opts.hugeUi ? hugeUi(opts.hugeUi === true ? 400 : Number(opts.hugeUi)) : null;
    this.widgets = (opts.widgets ?? (huge ? huge.widgets : demoWidgets)).map((w) => ({ ...w }));
    this.values = { ...(opts.values ?? (huge ? huge.values : initialValues)) };
    this.flaked = false;
    this.rev = 1;
    this.bootAt = Date.now();
    this.tokens = new Set();
    this.failed = 0;
    this.lockUntil = 0;
    this.clientClock = null; // { unix, tz, at }
    this.clients = new Set();
    this.dialogs = new Map();
    this.ota = null;
    this.logs = new Map(); // widget id -> last lines
    this.wifi = { st: "connected", ip: "192.168.1.50", ssid: "Home", rssi: -58 };
    this.timers = [];
  }

  // ---- lifecycle -------------------------------------------------------
  listen(port = 8080, host = "0.0.0.0") {
    this.http = createServer((req, res) => {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end(`espFace fake device "${this.name}" id ${this.id}. Connect a client to ws://<host>:${port}/ws\n`);
    });
    this.wss = new WebSocketServer({ server: this.http, path: "/ws" });
    this.wss.on("connection", (ws) => this.onConnect(ws));
    return new Promise((resolve) => this.http.listen(port, host, () => {
      this.port = this.http.address().port;
      this.log(`listening on ws://${host}:${this.port}/ws (pin: ${this.pin ? "set" : "none"})`);
      if (this.simulate) this.startSimulation();
      resolve(this.port);
    }));
  }

  close() {
    for (const t of this.timers) clearInterval(t);
    for (const c of this.clients) c.ws.terminate();
    this.wss?.close();
    return new Promise((r) => this.http?.close(() => r()));
  }

  log(...a) { if (!this.quiet) console.log("[fake]", ...a); }
  up() { return Date.now() - this.bootAt; }
  now() {
    if (this.clientClock) return this.clientClock.unix + Math.floor((Date.now() - this.clientClock.at) / 1000);
    return 0;
  }
  caps() { return ["wifi", "ota", "otaurl", "chart", "pin", "reboot", "info"]; }
  widget(id) { return this.widgets.find((w) => w.id === id); }
  firstPage() { return this.widgets.find((w) => w.ty === "page")?.id; }

  // ---- connections -----------------------------------------------------
  onConnect(ws) {
    const c = { ws, authed: false, nonce: null, page: this.firstPage(), dirty: new Set(), flushTimer: null, hello: false, queue: [], pumping: false, sent: 0 };
    this.clients.add(c);
    const rx = (data, isBinary) => (isBinary ? this.onBinary(c, data) : this.onText(c, data));
    ws.on("message", (data, isBinary) => (this.latency ? setTimeout(rx, this.latency, data, isBinary) : rx(data, isBinary)));
    ws.on("close", () => { this.clients.delete(c); clearTimeout(c.flushTimer); c.queue.length = 0; });
    ws.on("error", () => {});
  }

  send(c, msg) {
    if (c.ws.readyState !== 1) return;
    const text = JSON.stringify(msg);
    if (!this.latency && !this.slowUi && !this.dropEvery) return c.ws.send(text);
    c.queue.push({ text, ui: msg.t === "ui" });
    this.pump(c);
  }

  // Sequential sender so fragments, latency and drop counting never interleave.
  pump(c) {
    if (c.pumping) return;
    const item = c.queue.shift();
    if (!item) return;
    c.pumping = true;
    const done = () => { c.pumping = false; this.pump(c); };
    const run = () => {
      if (c.ws.readyState !== 1) { c.queue.length = 0; return done(); }
      const drop = this.dropEvery && ++c.sent >= this.dropEvery;
      const after = () => { if (drop) { c.sent = 0; c.ws.close(4000, "drop-every"); } done(); };
      if (item.ui && this.slowUi) return this.sendFragmented(c, item.text, after);
      c.ws.send(item.text, after);
    };
    if (this.latency) setTimeout(run, this.latency); else run();
  }

  sendFragmented(c, text, cb) {
    const buf = Buffer.from(text, "utf8");
    let off = 0;
    const step = () => {
      if (c.ws.readyState !== 1) return cb();
      const end = Math.min(buf.length, off + this.fragmentSize);
      const fin = end >= buf.length;
      c.ws.send(buf.subarray(off, end), { fin, binary: false }, () => { off = end; if (fin) cb(); else setTimeout(step, this.fragmentDelay); });
    };
    step();
  }
  err(c, code, msg, ref) { this.send(c, { t: "err", code, msg, ...(ref ? { ref } : {}) }); }
  broadcast(msg, filter = () => true) { for (const c of this.clients) if (c.authed && filter(c)) this.send(c, msg); }

  onText(c, data) {
    if (data.length > 2048) return this.err(c, ERR.big, "message too large");
    let m;
    try { m = JSON.parse(data.toString()); } catch { return this.err(c, ERR.json, "bad json"); }
    if (!m || typeof m.t !== "string") return this.err(c, ERR.json, "missing t");
    if (m.t === "hello") return this.onHello(c, m);
    if (m.t === "auth") return this.onAuth(c, m);
    if (!c.authed) return this.err(c, ERR.unauth, "unauthorized", m.t);
    const h = this["on_" + m.t];
    if (h) h.call(this, c, m); // unknown types are ignored by spec
  }

  onHello(c, m) {
    const authed = [...this.clients].filter((x) => x.authed && x !== c).length;
    if (authed >= this.maxClients) { this.err(c, ERR.busy, "too many clients", "hello"); return c.ws.close(); }
    c.hello = true;
    const base = { t: "hello", v: PROTO_V, name: this.name, id: this.id, proj: this.proj, icon: "thermostat", fw: "0.0.1-fake", auth: this.pin ? "pin" : "none", up: this.up(), caps: this.caps() };
    if (!this.pin || (m.tok && this.tokens.has(m.tok))) {
      this.send(c, { ...base, ok: true });
      return this.authenticated(c);
    }
    const lock = this.lockLeft();
    if (lock) return this.send(c, { ...base, ok: false, lock });
    c.nonce = randomBytes(16).toString("hex");
    this.send(c, { ...base, ok: false, nonce: c.nonce });
  }

  lockLeft() { return Math.max(0, Math.ceil((this.lockUntil - Date.now()) / 1000)); }

  onAuth(c, m) {
    if (!c.hello || !this.pin) return this.err(c, ERR.unauth, "hello first", "auth");
    const lock = this.lockLeft();
    if (lock) return this.send(c, { t: "auth", ok: false, lock });
    if (!c.nonce || typeof m.mac !== "string") return this.err(c, ERR.pin, "bad auth", "auth");
    const expect = hmacPin(this.pin, c.nonce, this.id);
    const ok = m.mac.length === expect.length && timingSafeEqual(Buffer.from(m.mac), Buffer.from(expect));
    c.nonce = null;
    if (!ok) {
      this.failed++;
      if (this.failed >= LOCK_AFTER) { this.failed = 0; this.lockUntil = Date.now() + LOCK_SECONDS * 1000; return this.send(c, { t: "auth", ok: false, lock: LOCK_SECONDS }); }
      c.nonce = randomBytes(16).toString("hex"); // allow retry on the same connection
      return this.send(c, { t: "auth", ok: false, left: LOCK_AFTER - this.failed });
    }
    this.failed = 0;
    if (this.flakyAuth && !this.flaked) { this.flaked = true; return this.err(c, ERR.pin, "flaky auth", "auth"); }
    const tok = randomBytes(16).toString("hex");
    this.tokens.add(tok);
    this.send(c, { t: "auth", ok: true, tok });
    this.authenticated(c);
  }

  authenticated(c) {
    c.authed = true;
    this.send(c, { t: "ui", rev: this.rev, w: this.widgets });
    this.send(c, { t: "upd", v: this.visibleValues(c) });
    for (const [id, lines] of this.logs) for (const l of lines) this.send(c, { t: "log", id, ...l });
  }

  visibleValues(c) {
    const out = {};
    for (const w of this.widgets) {
      if (!(w.id in this.values)) continue;
      if ((w.page ?? this.firstPage()) !== c.page) continue;
      out[w.id] = this.values[w.id];
    }
    return out;
  }

  // ---- value updates ---------------------------------------------------
  set(id, v) {
    this.values[id] = v;
    for (const c of this.clients) if (c.authed) { c.dirty.add(id); this.scheduleFlush(c); }
  }

  scheduleFlush(c) {
    if (c.flushTimer) return;
    c.flushTimer = setTimeout(() => {
      c.flushTimer = null;
      const v = {};
      for (const id of c.dirty) {
        const w = this.widget(id);
        if (w && (w.page ?? this.firstPage()) === c.page) v[id] = this.values[id];
      }
      c.dirty.clear();
      if (Object.keys(v).length) this.send(c, { t: "upd", v });
    }, FLUSH_MS);
  }

  pushPoint(id, s, value, ts = this.up()) { this.broadcast({ t: "pts", id, s, p: [[ts, value]] }); }
  toast(lvl, msg) { this.broadcast({ t: "toast", lvl, msg }); }
  logLine(id, msg, c) {
    const line = { msg, ts: this.up(), ...(c ? { c } : {}) };
    if (id) {
      const arr = this.logs.get(id) ?? [];
      arr.push(line); while (arr.length > this.logHistory) arr.shift();
      this.logs.set(id, arr);
    }
    this.broadcast({ t: "log", ...(id ? { id } : {}), ...line });
  }
  prop(id, p) {
    const w = this.widget(id);
    if (!w) return;
    Object.assign(w, p);
    this.broadcast({ t: "prop", id, p });
  }
  rebuild() { this.rev++; for (const c of this.clients) if (c.authed) this.authenticated(c); }

  dialog(kind, msg, opts = {}) {
    const id = "d" + (this.dialogs.size + 1 + Math.floor(Math.random() * 1000)).toString(36).slice(0, 8);
    const timeout = opts.timeout ?? 60;
    return new Promise((resolve) => {
      const timer = setTimeout(() => finish({ ok: false }), timeout * 1000);
      const finish = (ans) => { clearTimeout(timer); this.dialogs.delete(id); this.broadcast({ t: "dlg", id, close: true }); resolve(ans); };
      this.dialogs.set(id, finish);
      this.broadcast({ t: "dlg", id, kind, msg, ...(opts.title ? { title: opts.title } : {}), ...(opts.def !== undefined ? { def: opts.def } : {}), timeout });
    });
  }

  // ---- C→D handlers ----------------------------------------------------
  on_time(c, m) {
    if (!Number.isInteger(m.unix)) return this.err(c, ERR.value, "bad time", "time");
    this.clientClock = { unix: m.unix, tz: m.tz ?? 0, at: Date.now() };
    this.set("now", this.now());
  }

  on_page(c, m) {
    if (!this.widget(m.id) || this.widget(m.id).ty !== "page") return this.err(c, ERR.id, "unknown page", "page");
    c.page = m.id;
    c.dirty.clear();
    this.send(c, { t: "upd", v: this.visibleValues(c) });
  }

  on_set(c, m) {
    const w = this.widget(m.id);
    if (!w) return this.err(c, ERR.id, "unknown widget", "set");
    if (w.ro || w.dis || !validValue(w, m.v)) { this.err(c, ERR.value, "bad value", "set"); c.dirty.add(m.id); return this.scheduleFlush(c); }
    this.set(m.id, m.v);
    if (m.id === "pump") this.logLine("term", `pump ${m.v ? "on" : "off"}`);
    if (m.id === "target") this.pushPoint("tchart", "target", m.v);
  }

  on_ev(c, m) {
    const w = this.widget(m.id);
    if (!w) return this.err(c, ERR.id, "unknown widget", "ev");
    switch (m.id) {
      case "reset": this.set("ok", true); this.prop("temp", { color: "#00ff00" }); return this.toast("info", "Error cleared");
      case "horn": return this.logLine("term", `horn ${m.v ? "pressed" : "released"}`, "#ff8800");
      case "pad": return this.logLine("term", `dpad ${m.v}`);
      case "erase":
        return this.dialog("confirm", "Erase all stored data?", { title: "Erase" }).then((a) => {
          if (a.ok) { this.set("n", 0); this.set("notes", ""); this.toast("warn", "Erased"); this.logLine("term", "erased by client", "#ff0000"); }
          else this.toast("info", "Erase cancelled");
        });
      case "rename":
        return this.dialog("prompt", "New device name", { def: this.name }).then((a) => {
          if (a.ok && typeof a.v === "string" && a.v.trim()) { this.name = a.v.trim().slice(0, 32); this.set("name", this.name); this.toast("info", `Renamed to ${this.name}`); }
        });
      default: return this.logLine("term", `event ${m.id}`);
    }
  }

  on_dlg(c, m) {
    const finish = this.dialogs.get(m.id);
    if (!finish) return this.err(c, ERR.id, "unknown dialog", "dlg");
    finish({ ok: !!m.ok, v: m.v });
  }

  on_sys(c, m) {
    const reply = (extra) => this.send(c, { t: "sys", cmd: m.cmd, ...extra });
    switch (m.cmd) {
      case "info":
        return reply({ chip: "FAKE", fw: "0.0.1-fake", repo: "manzari/espFace", about: "Node fake device", rr: "power", heap: 200000, heapmin: 180000, up: this.up(), ip: this.wifi.ip, ssid: this.wifi.ssid, rssi: this.wifi.rssi, mac: "aa:bb:cc:dd:ee:ff", time: this.now(), clients: [...this.clients].filter((x) => x.authed).length });
      case "wifi.scan":
        return reply({ ap: [{ ssid: "Home", rssi: -55, enc: true }, { ssid: "Cafe", rssi: -80, enc: false }, { ssid: "Neighbour", rssi: -88, enc: true }] });
      case "wifi.status":
        return reply({ ...this.wifi });
      case "wifi.set":
        if (typeof m.ssid !== "string") return this.err(c, ERR.value, "ssid required", "wifi.set");
        this.wifi = { st: "connecting", ssid: m.ssid };
        this.broadcast({ t: "sys", cmd: "wifi.status", ...this.wifi });
        setTimeout(() => { this.wifi = { st: m.pass === "fail" ? "failed" : "connected", ssid: m.ssid, ip: "192.168.1.50", rssi: -60 }; this.broadcast({ t: "sys", cmd: "wifi.status", ...this.wifi }); }, 1500);
        return;
      case "reboot":
        reply({ ok: true });
        return setTimeout(() => { this.bootAt = Date.now(); for (const x of this.clients) x.ws.close(); }, 500);
      case "pin.set":
        if (typeof m.pin !== "string" || (m.pin.length && (m.pin.length < 4 || m.pin.length > 32))) return this.err(c, ERR.value, "pin 4..32 chars", "pin.set");
        this.pin = m.pin || null; this.tokens.clear();
        return reply({ ok: true });
      case "revoke":
        this.tokens.clear();
        reply({ ok: true });
        for (const x of this.clients) if (x !== c) x.ws.close();
        return;
      case "ota.begin":
        if (this.ota) return this.err(c, ERR.busy, "ota in progress", "ota.begin");
        if (!Number.isInteger(m.size) || !/^[0-9a-f]{32}$/.test(m.md5 ?? "")) return this.err(c, ERR.value, "size and md5 required", "ota.begin");
        this.ota = { c, size: m.size, md5: m.md5, got: 0, hash: createHash("md5"), lastPct: -1, lastAt: 0 };
        return reply({ ok: true });
      case "ota.abort":
        this.ota = null;
        return reply({ ok: true });
      case "ota.url": {
        if (this.ota) return this.err(c, ERR.busy, "ota in progress", "ota.url");
        if (typeof m.url !== "string" || !/^https?:\/\//.test(m.url)) return this.err(c, ERR.value, "bad url", "ota.url");
        reply({ ok: true });
        this.ota = { url: m.url };
        let pct = 0;
        const t = setInterval(() => {
          pct += 20;
          this.broadcast({ t: "sys", cmd: "ota.progress", pct: Math.min(pct, 100) });
          if (pct >= 100) { clearInterval(t); this.ota = null; this.broadcast({ t: "sys", cmd: "ota.done", ok: true }); }
        }, 500);
        return;
      }
      default:
        return this.err(c, ERR.value, "unknown cmd", "sys");
    }
  }

  onBinary(c, data) {
    const o = this.ota;
    if (!o || o.c !== c) return this.err(c, ERR.ota, "no ota session", "ota");
    o.hash.update(data); o.got += data.length;
    const pct = Math.min(100, Math.floor((o.got * 100) / o.size));
    if (pct !== o.lastPct && Date.now() - o.lastAt >= 500) { o.lastPct = pct; o.lastAt = Date.now(); this.send(c, { t: "sys", cmd: "ota.progress", pct }); }
    if (o.got >= o.size) {
      this.ota = null;
      const ok = o.got === o.size && o.hash.digest("hex") === o.md5;
      this.send(c, { t: "sys", cmd: "ota.progress", pct: 100 });
      this.send(c, { t: "sys", cmd: "ota.done", ok, ...(ok ? {} : { msg: "md5 mismatch" }) });
      if (ok) setTimeout(() => { this.bootAt = Date.now(); for (const x of this.clients) x.ws.close(); }, 1000);
    }
  }

  // ---- simulation ------------------------------------------------------
  startSimulation() {
    let tick = 0, hot = false;
    this.timers.push(setInterval(() => {
      tick++;
      const temp = Math.round((60 + 30 * Math.sin(tick / 20) + (this.values.pump ? 5 : 0)) * 10) / 10;
      this.set("temp", temp);
      this.pushPoint("tchart", "temp", temp);
      this.set("level", Math.round(50 + 40 * Math.cos(tick / 37)));
      this.set("bal", Math.round(80 * Math.sin(tick / 11)));
      this.set("disp", Math.round((1.5 + 0.5 * Math.sin(tick / 9)) * 100) / 100);
      if (tick % 5 === 0) this.set("rgb", this.values.rgb === 0x00ff00 ? 0x0000ff : 0x00ff00);
      if (tick % 10 === 0 && this.clientClock) this.set("now", this.now());
      if (tick % 3 === 0) this.logLine("term", `tick ${tick} temp ${temp}`);
      if (temp > 85 && !hot) { hot = true; this.set("ok", false); this.prop("temp", { color: "#ff0000", lbl: "Temperature (HOT)" }); this.toast("warn", "Overheating"); }
      if (temp < 80 && hot) { hot = false; this.prop("temp", { color: "#00ff00", lbl: "Temperature" }); }
    }, 1000));
  }
}

export function hmacPin(pin, nonceHex, deviceId) {
  return createHmac("sha256", Buffer.from(pin, "utf8")).update(nonceHex + deviceId).digest("hex");
}

// ---- CLI ---------------------------------------------------------------
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/^.*\//, ""))) {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log("usage: espface-fake-device [--port=8080] [--pin=1234] [--name=Boiler] [--id=a1b2c3] [--no-sim]\n" +
      "  hardening: [--drop-every N] [--latency ms] [--slow-ui] [--max-clients N] [--flaky-auth] [--huge-ui[=N]]");
    process.exit(0);
  }
  const dev = new FakeDevice({
    pin: args.pin, name: args.name, id: args.id, simulate: !args["no-sim"],
    dropEvery: Number(args["drop-every"] ?? 0), latency: Number(args.latency ?? 0), slowUi: !!args["slow-ui"],
    maxClients: args["max-clients"] !== undefined ? Number(args["max-clients"]) : undefined,
    flakyAuth: !!args["flaky-auth"], hugeUi: args["huge-ui"] === true ? true : args["huge-ui"] ? Number(args["huge-ui"]) : false,
  });
  dev.listen(Number(args.port ?? process.env.PORT ?? 8080));
}

// --k=v, --k v (when the next arg is not a flag) and bare --k.
export function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const [k, v] = a.slice(2).split("=");
    if (v !== undefined) out[k] = v;
    else if (i + 1 < argv.length && !argv[i + 1].startsWith("--") && !["slow-ui", "flaky-auth", "no-sim", "help"].includes(k)) out[k] = argv[++i];
    else out[k] = true;
  }
  return out;
}
