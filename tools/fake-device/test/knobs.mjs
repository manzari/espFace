// Hardening knobs: drop-every, latency, slow-ui, max-clients, flaky-auth, huge-ui, CLI parsing.
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import WebSocket from "ws";
import { FakeDevice, hmacPin, parseArgs } from "../src/index.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const { makeValidator } = await import(join(here, "..", "..", "..", "protocol", "test", "validate.mjs"));
const v = makeValidator();

let failures = 0;
setTimeout(() => { console.log("FAIL: knobs test timed out"); process.exit(1); }, 60000).unref();
const assert = (cond, msg) => { if (!cond) { failures++; console.log("FAIL", msg); } else if (process.env.DEBUG) console.log("ok", msg); };

function connect(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const queue = [], waiters = [];
  const st = { count: 0, closed: null, bytes: 0 };
  ws.on("message", (d, bin) => {
    if (bin) return;
    st.count++; st.bytes += d.length;
    const m = JSON.parse(d.toString());
    if (!v.d2c(m)) { failures++; console.log("FAIL schema d2c:", JSON.stringify(m).slice(0, 200)); }
    if (waiters.length) waiters.shift()(m); else queue.push(m);
  });
  ws.on("close", (code) => { st.closed = code; while (waiters.length) waiters.shift()(null); });
  const next = () => queue.length ? Promise.resolve(queue.shift()) : new Promise((r) => waiters.push(r));
  const until = async (pred, max = 200) => { for (let i = 0; i < max; i++) { const m = await next(); if (m === null) return null; if (pred(m)) return m; } throw new Error("message not seen"); };
  const send = (m) => ws.send(JSON.stringify(m));
  const closed = () => st.closed !== null ? Promise.resolve(st.closed) : new Promise((r) => ws.on("close", r));
  return new Promise((r) => ws.on("open", () => r({ ws, next, until, send, st, closed })));
}

// 1. drop-every: exactly N messages then close code 4000, next connection works again
{
  const dev = new FakeDevice({ quiet: true, simulate: false, dropEvery: 3 });
  const port = await dev.listen(0, "127.0.0.1");
  let c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  const code = await c.closed();
  assert(code === 4000 && c.st.count === 3, `drop-every closes after 3 messages (got ${c.st.count}, code ${code})`);
  c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  const h = await c.next();
  assert(h?.t === "hello" && h.ok === true, "reconnect after a drop is served");
  await c.closed();
  await dev.close();
}

// 2. latency: hello round trip takes at least 2 x latency
{
  const dev = new FakeDevice({ quiet: true, simulate: false, latency: 100 });
  const port = await dev.listen(0, "127.0.0.1");
  const c = await connect(port);
  const t0 = Date.now();
  c.send({ t: "hello", v: 1, client: "web" });
  await c.next();
  const dt = Date.now() - t0;
  assert(dt >= 190, `latency 100 ms each way -> hello RTT ${dt} ms`);
  c.ws.close();
  await dev.close();
}

// 3. slow-ui: the ui arrives intact (fragments reassembled by the client) and takes fragment delays
{
  const dev = new FakeDevice({ quiet: true, simulate: false, slowUi: true, fragmentSize: 256, fragmentDelay: 5 });
  const port = await dev.listen(0, "127.0.0.1");
  const c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  const t0 = Date.now();
  const ui = await c.until((m) => m.t === "ui");
  const dt = Date.now() - t0;
  const bytes = JSON.stringify(ui).length;
  const frags = Math.ceil(bytes / 256);
  assert(ui.w.length > 30 && ui.w.every((w) => v.widget(w)), "slow-ui delivers a complete, valid ui");
  assert(dt >= (frags - 1) * 5 * 0.8, `slow-ui took ${dt} ms for ${frags} fragments`);
  const upd = await c.until((m) => m.t === "upd");
  assert(upd && "temp" in upd.v, "messages queued behind the fragmented ui still arrive in order");
  c.ws.close();
  await dev.close();
}

// 4. max-clients: the N+1th hello gets err 9 and is closed
{
  const dev = new FakeDevice({ quiet: true, simulate: false, maxClients: 1 });
  const port = await dev.listen(0, "127.0.0.1");
  const a = await connect(port);
  a.send({ t: "hello", v: 1, client: "web" });
  await a.until((m) => m.t === "upd");
  const b = await connect(port);
  b.send({ t: "hello", v: 1, client: "web" });
  const e = await b.next();
  assert(e?.t === "err" && e.code === 9 && e.ref === "hello", "second client gets err 9");
  await b.closed();
  a.ws.close();
  await a.closed();
  const c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  const h = await c.next();
  assert(h?.t === "hello" && h.ok === true, "slot is free again after the first client left");
  c.ws.close();
  await dev.close();
}

// 5. flaky-auth: first correct auth -> err 5 once, the retry (new hello, new nonce) succeeds
{
  const dev = new FakeDevice({ quiet: true, simulate: false, pin: "1234", flakyAuth: true });
  const port = await dev.listen(0, "127.0.0.1");
  const c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  let h = await c.next();
  c.send({ t: "auth", mac: hmacPin("1234", h.nonce, h.id) });
  const e = await c.next();
  assert(e?.t === "err" && e.code === 5 && e.ref === "auth", "first correct auth answered with err 5");
  c.send({ t: "hello", v: 1, client: "web" });
  h = await c.next();
  assert(h?.t === "hello" && h.ok === false && h.nonce, "hello after the flake issues a fresh nonce");
  c.send({ t: "auth", mac: hmacPin("1234", h.nonce, h.id) });
  const a = await c.next();
  assert(a?.t === "auth" && a.ok === true && a.tok, "second auth succeeds");
  c.ws.close();
  await dev.close();
}

// 6. huge-ui: several hundred valid widgets, ~100 KB, demo ids still present, values for every input
{
  const dev = new FakeDevice({ quiet: true, simulate: false, hugeUi: true });
  const port = await dev.listen(0, "127.0.0.1");
  const c = await connect(port);
  c.send({ t: "hello", v: 1, client: "web" });
  const ui = await c.until((m) => m.t === "ui");
  const bytes = JSON.stringify(ui).length;
  assert(ui.w.length >= 440 && ui.w.length <= 500, `huge-ui has ${ui.w.length} widgets (schema cap 500)`);
  assert(bytes >= 90_000, `huge-ui is ${bytes} bytes`);
  assert(ui.w.every((w) => v.widget(w)), "every generated widget validates against the schema");
  assert(new Set(ui.w.map((w) => w.id)).size === ui.w.length, "generated ids are unique");
  assert(ui.w.some((w) => w.id === "temp"), "demo widgets are kept");
  const upd = await c.until((m) => m.t === "upd");
  assert("temp" in upd.v, "first upd carries the first page");
  c.send({ t: "page", id: "p1" });
  const pageUpd = await c.until((m) => m.t === "upd" && "w200" in m.v);
  assert(Object.keys(pageUpd.v).length >= 150, `page upd for a generated page holds ${Object.keys(pageUpd.v).length} values`);
  c.ws.close();
  await dev.close();
}

// 7. CLI parsing: --k=v, --k v, bare flags
{
  const a = parseArgs(["--drop-every", "5", "--latency=200", "--slow-ui", "--max-clients", "2", "--flaky-auth", "--huge-ui", "--pin", "1234", "--port=18080"]);
  assert(a["drop-every"] === "5" && a.latency === "200" && a["slow-ui"] === true && a["max-clients"] === "2" && a["flaky-auth"] === true && a["huge-ui"] === true && a.pin === "1234" && a.port === "18080", "parseArgs handles both flag styles");
  const b = parseArgs(["--huge-ui=300", "--no-sim"]);
  assert(b["huge-ui"] === "300" && b["no-sim"] === true, "parseArgs value for huge-ui and bare no-sim");
}

console.log(`knobs: ${failures} failures`);
process.exit(failures ? 1 : 0);
