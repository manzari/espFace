// Smoke test: drives a full session against the fake device and validates every device message against the schema.
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createHash } from "node:crypto";
import WebSocket from "ws";
import { FakeDevice, hmacPin } from "../src/index.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const { makeValidator } = await import(join(here, "..", "..", "..", "protocol", "test", "validate.mjs"));
const v = makeValidator();

let checked = 0, failures = 0;
setTimeout(() => { console.log("FAIL: smoke test timed out"); process.exit(1); }, 30000).unref();
const assert = (cond, msg) => { if (!cond) { failures++; console.log("FAIL", msg); } };

function connect(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const queue = [];
  const waiters = [];
  ws.on("message", (d, bin) => {
    if (bin) return;
    const m = JSON.parse(d.toString());
    checked++;
    if (process.env.DEBUG) console.log("<-", JSON.stringify(m).slice(0, 120));
    if (!v.d2c(m)) { failures++; console.log("FAIL schema d2c:", JSON.stringify(m).slice(0, 200), v.d2c.errors?.slice(0, 3)); }
    if (waiters.length) waiters.shift()(m); else queue.push(m);
  });
  const next = () => queue.length ? Promise.resolve(queue.shift()) : new Promise((r) => waiters.push(r));
  const until = async (pred, max = 50) => { for (let i = 0; i < max; i++) { const m = await next(); if (pred(m)) return m; } throw new Error("message not seen"); };
  const send = (m) => { assert(v.c2d(m), "c2d schema " + JSON.stringify(m)); ws.send(JSON.stringify(m)); };
  return new Promise((r) => ws.on("open", () => r({ ws, next, until, send })));
}

const dev = new FakeDevice({ pin: "1234", quiet: true, simulate: false });
const port = await dev.listen(0, "127.0.0.1");

// 1. PIN auth with HMAC, wrong then right
let c = await connect(port);
c.send({ t: "hello", v: 1, client: "app" });
let h = await c.next();
assert(h.t === "hello" && h.ok === false && /^[0-9a-f]{32}$/.test(h.nonce), "hello asks for pin");
c.send({ t: "auth", mac: "0".repeat(64) });
let a = await c.next();
assert(a.t === "auth" && a.ok === false && a.left === 4, "wrong mac rejected with left=4");
// retry uses the fresh nonce the device generated; the fake does not resend hello, so reconnect to get it
c.ws.close();
c = await connect(port);
c.send({ t: "hello", v: 1, client: "app" });
h = await c.next();
c.send({ t: "auth", mac: hmacPin("1234", h.nonce, h.id) });
a = await c.next();
assert(a.ok === true && /^[0-9a-f]{32}$/.test(a.tok), "correct mac yields token");
const tok = a.tok;
const ui = await c.next();
assert(ui.t === "ui" && ui.w.length > 30, "ui follows auth");
for (const w of ui.w) assert(v.widget(w), "widget schema " + w.id);
const upd = await c.next();
assert(upd.t === "upd" && "temp" in upd.v && !("joy" in upd.v), "first upd holds only first-page values");

// 2. time, page switch, set, invalid set
c.send({ t: "time", unix: 1728700000, tz: 120 });
c.send({ t: "page", id: "io" });
const pageUpd = await c.until((m) => m.t === "upd" && "joy" in m.v);
assert(!("temp" in pageUpd.v), "page upd excludes other pages");
c.send({ t: "set", id: "joy", v: [10, -10] });
const echo = await c.until((m) => m.t === "upd" && "joy" in m.v);
assert(JSON.stringify(echo.v.joy) === "[10,-10]", "set echoed via upd");
c.send({ t: "set", id: "temp", v: 1 });
const e = await c.until((m) => m.t === "err");
assert(e.code === 7, "set on ro widget -> err 7");
c.send({ t: "page", id: "main" });
await c.until((m) => m.t === "upd" && "temp" in m.v);

// 3. events, dialogs, props
c.send({ t: "ev", id: "erase" });
const dlg = await c.until((m) => m.t === "dlg" && m.kind === "confirm");
c.send({ t: "dlg", id: dlg.id, ok: true });
await c.until((m) => m.t === "dlg" && m.close === true);
await c.until((m) => m.t === "toast" && m.msg === "Erased");
c.send({ t: "ev", id: "reset" });
await c.until((m) => m.t === "prop" && m.id === "temp");
c.send({ t: "ev", id: "horn", v: 1 });
await c.until((m) => m.t === "log" && m.id === "term");

// 4. sys: info, wifi, ota push with md5
c.send({ t: "sys", cmd: "info" });
const info = await c.until((m) => m.t === "sys" && m.cmd === "info");
assert(info.time === 1728700000 || info.time === 1728700001, "info time from client clock");
c.send({ t: "sys", cmd: "wifi.scan" });
await c.until((m) => m.cmd === "wifi.scan" && m.ap.length === 3);
const img = Buffer.alloc(10000, 7);
c.send({ t: "sys", cmd: "ota.begin", size: img.length, md5: createHash("md5").update(img).digest("hex") });
await c.until((m) => m.cmd === "ota.begin" && m.ok === true);
for (let i = 0; i < img.length; i += 4096) c.ws.send(img.subarray(i, i + 4096));
const done = await c.until((m) => m.cmd === "ota.done");
assert(done.ok === true, "ota done ok");
await new Promise((r) => c.ws.on("close", r));

// 5. token reconnect, revoke
c = await connect(port);
c.send({ t: "hello", v: 1, client: "web", tok });
h = await c.next();
assert(h.ok === true && !h.nonce, "token hello authenticates");
await c.next(); await c.next();
c.send({ t: "sys", cmd: "revoke" });
await c.until((m) => m.cmd === "revoke" && m.ok === true);
c.ws.close();
c = await connect(port);
c.send({ t: "hello", v: 1, client: "web", tok });
h = await c.next();
assert(h.ok === false, "revoked token rejected");

// 6. lockout after 5 wrong attempts
for (let i = 0; i < 5; i++) { c.send({ t: "auth", mac: "f".repeat(64) }); a = await c.next(); }
assert(a.ok === false && a.lock === 60, "fifth failure locks for 60 s");
c.ws.close();
c = await connect(port);
c.send({ t: "hello", v: 1, client: "app" });
h = await c.next();
assert(h.ok === false && h.lock > 0 && !h.nonce, "hello during lockout carries lock");
c.ws.close();

await dev.close();
console.log(`${checked} device messages schema-checked, ${failures} failures`);
process.exit(failures ? 1 : 0);
