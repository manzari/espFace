// Reconnect, backoff, token resume, slow/huge ui, busy, flaky auth and buffer bounds against the in-process fake device.
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { Session } from "../src/session";
import { Store, CHART_MAX_POINTS, LOG_MAX_LINES } from "../src/store";
import { BACKOFF_CAP_MS, backoffDelay } from "../src/transport/ws";
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore plain JS module from tools/
import { FakeDevice } from "../../tools/fake-device/src/index.mjs";

type Fake = { listen(port: number, host: string): Promise<number>; close(): Promise<void>; clients: Set<unknown>; tokens: Set<string> };

const fast = { backoff: () => 15 };
const devices: Fake[] = [];
const sessions: Session[] = [];

async function device(opts: Record<string, unknown>): Promise<string> {
  const d = new FakeDevice({ quiet: true, simulate: false, ...opts }) as Fake;
  devices.push(d);
  const port = await d.listen(0, "127.0.0.1");
  return `127.0.0.1:${port}`;
}

function session(host: string, store = new Store()) {
  const s = new Session(store, host, fast);
  sessions.push(s);
  s.start();
  return s;
}

async function until(cond: () => boolean, what: string, ms = 8000) {
  const end = Date.now() + ms;
  while (!cond()) { if (Date.now() > end) throw new Error(`timeout: ${what}`); await new Promise((r) => setTimeout(r, 5)); }
}

const connLog = (s: Store) => { const log: string[] = []; s.subscribe("conn", () => log.push(s.conn)); return log; };

beforeAll(() => {
  const m = new Map<string, string>();
  (globalThis as unknown as { localStorage: unknown }).localStorage = { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => m.set(k, v), removeItem: (k: string) => m.delete(k) };
});

afterEach(async () => {
  for (const s of sessions.splice(0)) s.stop();
  for (const d of devices.splice(0)) await d.close();
});

describe("backoff", () => {
  it("grows exponentially from 500 ms, caps at 30 s and jitters by +-25 %", () => {
    expect(backoffDelay(0, () => 0.5)).toBe(500);
    expect(backoffDelay(1, () => 0.5)).toBe(1000);
    expect(backoffDelay(5, () => 0.5)).toBe(16000);
    expect(backoffDelay(6, () => 0.5)).toBe(BACKOFF_CAP_MS);
    expect(backoffDelay(3, () => 0)).toBe(3000);
    expect(backoffDelay(3, () => 1)).toBe(5000);
    for (let a = 0; a < 40; a++) { const d = backoffDelay(a); expect(d).toBeGreaterThanOrEqual(375); expect(d).toBeLessThanOrEqual(BACKOFF_CAP_MS); }
    expect(backoffDelay(50, () => 1)).toBe(BACKOFF_CAP_MS);
  });
});

describe("reconnect against the fake device", () => {
  it("drop-every: resumes with the token, never re-prompts the PIN and keeps the last UI", async () => {
    const host = await device({ pin: "1234", dropEvery: 5 });
    const store = new Store();
    const log = connLog(store);
    const s = session(host, store);
    await until(() => store.conn === "pin", "pin prompt");
    await s.submitPin("1234");
    await until(() => store.conn === "ready" && store.widgets.size > 0, "ready");
    const widgets = store.widgets.size;
    // hello, auth, ui, upd = 4 messages; the 5th reply closes the socket
    s.sys("info");
    await until(() => store.conn === "offline", "drop");
    expect(store.widgets.size).toBe(widgets);
    expect(store.sysInfo).toBeNull();
    await until(() => store.conn === "ready", "reconnect");
    expect(store.widgets.size).toBe(widgets);
    expect(log.filter((c) => c === "pin").length).toBe(1);
    expect(s.ws.attempts).toBe(1);
    // a second drop cycle: hello(tok), ui, upd, then two more replies
    s.sys("info"); s.sys("info");
    await until(() => store.conn === "offline", "second drop");
    await until(() => store.conn === "ready", "second reconnect");
    expect(log.filter((c) => c === "pin").length).toBe(1);
    expect(s.ws.attempts).toBe(2);
  });

  it("manual reconnect is immediate and resets the backoff", async () => {
    const host = await device({});
    const store = new Store();
    const log = connLog(store);
    const s = session(host, store);
    await until(() => store.conn === "ready", "ready");
    log.length = 0;
    const t0 = Date.now();
    s.ws.reconnect(0);
    await until(() => log.includes("offline") && store.conn === "ready", "reopened");
    expect(Date.now() - t0).toBeLessThan(500);
  });

  it("stop() ends reconnecting and leaves no device session behind", async () => {
    const host = await device({});
    const store = new Store();
    const s = session(host, store);
    await until(() => store.conn === "ready", "ready");
    s.stop();
    await until(() => devices[0].clients.size === 0, "device saw the close");
    await new Promise((r) => setTimeout(r, 60));
    expect(devices[0].clients.size).toBe(0);
  });

  it("slow-ui: a fragmented ui message is reassembled before it is applied", async () => {
    const host = await device({ slowUi: true, fragmentSize: 200, fragmentDelay: 2 });
    const store = new Store();
    let uiEmits = 0;
    store.subscribe("layout", () => uiEmits++);
    session(host, store);
    await until(() => store.widgets.size > 0, "ui", 15000);
    expect(store.widgets.size).toBeGreaterThanOrEqual(40);
    expect(uiEmits).toBe(1);
    expect(store.pages().map((p) => p.id)).toEqual(["main", "io", "setup"]);
  });

  it("huge-ui: ~100 KB ui is applied and laid out quickly", async () => {
    const host = await device({ hugeUi: true });
    const store = new Store();
    const origApply = store.apply.bind(store);
    let applyMs = 0;
    store.apply = (m) => { const t = performance.now(); origApply(m); if (m.t === "ui") applyMs = performance.now() - t; };
    session(host, store);
    await until(() => store.widgets.size > 400, "ui", 15000);
    const t = performance.now();
    const pages = store.layout();
    const layoutMs = performance.now() - t;
    expect(pages.length).toBe(5);
    expect(applyMs).toBeLessThan(200);
    expect(layoutMs).toBeLessThan(50);
    console.log(`huge-ui: ${store.widgets.size} widgets, store.apply ${applyMs.toFixed(1)} ms, layout ${layoutMs.toFixed(1)} ms`);
  });

  it("max-clients: the extra client sees busy and gets in once a slot frees up", async () => {
    const host = await device({ maxClients: 1 });
    const a = new Store(), b = new Store();
    const sa = session(host, a);
    await until(() => a.conn === "ready", "a ready");
    session(host, b);
    await until(() => b.busy && b.conn === "offline", "b busy");
    expect(b.widgets.size).toBe(0);
    sa.stop();
    await until(() => b.conn === "ready", "b ready after a left");
    expect(b.busy).toBe(false);
  });

  it("flaky-auth: err 5 after a correct PIN is retried without asking again", async () => {
    const host = await device({ pin: "1234", flakyAuth: true });
    const store = new Store();
    const log = connLog(store);
    const s = session(host, store);
    await until(() => store.conn === "pin", "pin prompt");
    await s.submitPin("1234");
    await until(() => store.conn === "ready", "ready after retry");
    expect(log.filter((c) => c === "pin").length).toBe(1);
    expect(devices[0].tokens.size).toBe(1);
  });

  it("wrong PIN followed by err 5 re-prompts instead of hanging", async () => {
    const host = await device({ pin: "1234", flakyAuth: true });
    const store = new Store();
    const s = session(host, store);
    await until(() => store.conn === "pin", "pin prompt");
    await s.submitPin("0000");
    await until(() => store.authLeft === 4, "wrong pin counted");
    await s.submitPin("1234");
    await until(() => store.conn === "ready", "ready");
  });

  it("lockout: five wrong PINs lock, the state carries the countdown and a reconnect keeps it", async () => {
    const host = await device({ pin: "1234" });
    const store = new Store();
    const s = session(host, store);
    await until(() => store.conn === "pin", "pin prompt");
    for (let i = 0; i < 5; i++) {
      const before = store.version("conn");
      await s.submitPin("0000");
      await until(() => store.version("conn") !== before, `attempt ${i}`);
    }
    expect(store.conn).toBe("locked");
    expect(store.lockUntil - Date.now()).toBeGreaterThan(55000);
    s.ws.reconnect(0);
    await until(() => s.ws.open, "reopened");
    await until(() => !!store.device?.lock, "hello carries lock");
    expect(store.conn).toBe("locked");
  });

  it("200 fast reconnects leave no listeners or growing buffers behind", async () => {
    const host = await device({});
    const store = new Store();
    const log = connLog(store);
    const s = session(host, store);
    await until(() => store.conn === "ready", "ready");
    for (let i = 0; i < 200; i++) {
      const off = store.subscribe("v:temp", () => {});
      log.length = 0;
      s.ws.reconnect(0);
      // the offline phase can be shorter than a poll tick, so wait on the recorded transitions
      await until(() => log.includes("offline") && store.conn === "ready", `cycle ${i}`, 2000);
      off();
    }
    expect(store.listenerCount()).toBe(1);
    expect(s.ws.attempts).toBe(200);
    expect(devices[0].clients.size).toBe(1);
    expect(store.toasts.length).toBeLessThanOrEqual(5);
  });
});

describe("buffer bounds", () => {
  it("chart series never exceed the hard cap even with a huge window", () => {
    const s = new Store();
    s.apply({ t: "hello", v: 1, name: "x", id: "a1b2c3", auth: "none", ok: true, up: 0, caps: [] });
    s.apply({ t: "ui", rev: 1, w: [{ id: "c", ty: "chart", series: [{ id: "a" }], win: 10_000_000 }] });
    for (let i = 0; i < 12; i++) s.apply({ t: "pts", id: "c", s: "a", p: Array.from({ length: 1000 }, (_, k) => [2 ** 40 + i * 1000 + k, k] as [number, number]) });
    expect(s.charts.get("c")!.get("a")!.length).toBe(CHART_MAX_POINTS);
  });
  it("log widgets are capped below the device's cap when it is absurd, dialogs at ten", () => {
    const s = new Store();
    s.apply({ t: "ui", rev: 1, w: [{ id: "l", ty: "log", cap: 1_000_000 }] });
    for (let i = 0; i < LOG_MAX_LINES + 100; i++) s.apply({ t: "log", id: "l", msg: "x" + i });
    expect(s.logs.get("l")!.length).toBe(LOG_MAX_LINES);
    for (let i = 0; i < 15; i++) s.apply({ t: "dlg", id: "d" + i, kind: "confirm", msg: "?" });
    expect(s.dialogs.length).toBe(10);
  });
  it("buffers of widgets removed by a new ui are released", () => {
    const s = new Store();
    s.apply({ t: "ui", rev: 1, w: [{ id: "c", ty: "chart", series: [{ id: "a" }] }, { id: "l", ty: "log" }] });
    s.apply({ t: "pts", id: "c", s: "a", p: [[1, 1]] });
    s.apply({ t: "log", id: "l", msg: "x" });
    s.apply({ t: "ui", rev: 2, w: [{ id: "other", ty: "label" }] });
    expect(s.charts.size).toBe(0);
    expect(s.logs.size).toBe(0);
  });
});
