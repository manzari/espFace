import { describe, expect, it } from "vitest";
import type { D2C, HelloMsg, UiMsg } from "../src/proto/types";
import { Store } from "../src/store";
import { loadVectors } from "./vectors";

const vectors = loadVectors();
const d2c = vectors.filter((v) => v.dir === "d2c");
const showcase = vectors.find((v) => v.name === "ui full showcase")!.msg as unknown as UiMsg;
const hello = (up = 5000): HelloMsg => ({ t: "hello", v: 1, name: "Boiler", id: "a1b2c3", auth: "none", ok: true, up, caps: ["chart"] });

function fresh(now = 1_000_000) { const s = new Store(); s.now = () => now; s.apply(hello()); return s; }

describe("every d2c vector is accepted without throwing", () => {
  for (const vec of d2c) it(vec.name, () => { expect(() => new Store().apply(vec.msg as unknown as D2C)).not.toThrow(); });
  it("all valid d2c vectors in sequence on one store", () => {
    const s = new Store();
    for (const vec of d2c.filter((v) => v.valid !== false)) s.apply(vec.msg as unknown as D2C);
    expect(s.widgets.size).toBeGreaterThan(0);
  });
});

describe("ui model and layout", () => {
  it("parses the showcase and lays out pages, groups and rows", () => {
    const s = fresh();
    s.apply(showcase);
    expect(s.rev).toBe(7);
    expect(s.widgets.size).toBe(showcase.w.length);
    const pages = s.pages();
    expect(pages.map((p) => p.id)).toEqual(["main", "setup"]);
    expect(s.page).toBe("main");
    const main = pages[0];
    expect(main.blocks[0]).toMatchObject({ kind: "free", items: ["hdr"] });
    const sensors = main.blocks.find((b) => b.id === "sensors")!;
    expect(sensors.kind).toBe("group");
    expect(sensors.items).toContain("temp");
    const control = main.blocks.find((b) => b.id === "control")!;
    const row = control.items.find((i) => typeof i !== "string") as { id: string; items: string[] };
    expect(row.id).toBe("r1");
    expect(row.items).toEqual(["pump", "target"]);
    expect(pages[1].blocks.flatMap((b) => b.items)).toEqual(["help", "name", "pw", "notes"]);
  });
  it("widgets without pages still render on an implicit page", () => {
    const s = fresh();
    s.apply({ t: "ui", rev: 1, w: [{ id: "temp", ty: "label" }] });
    expect(s.pages()).toHaveLength(1);
    expect(s.pages()[0].blocks[0].items).toEqual(["temp"]);
  });
  it("inherits the page from the group when the widget has none", () => {
    const s = fresh();
    s.apply({ t: "ui", rev: 1, w: [{ id: "a", ty: "page" }, { id: "b", ty: "page" }, { id: "g", ty: "group", page: "b" }, { id: "x", ty: "label", grp: "g" }] });
    expect(s.pages()[1].blocks[0].items).toEqual(["x"]);
  });
  it("prop merges into the model and only structural props invalidate the layout", () => {
    const s = fresh();
    s.apply(showcase);
    let w = 0, layout = 0;
    s.subscribe("w:temp", () => w++);
    s.subscribe("layout", () => layout++);
    s.apply({ t: "prop", id: "temp", p: { lbl: "Temp (HOT)", color: "#ff0000" } });
    expect(s.widgets.get("temp")).toMatchObject({ lbl: "Temp (HOT)", color: "#ff0000", ty: "gauge", max: 120 });
    expect(w).toBe(1); expect(layout).toBe(0);
    s.apply({ t: "prop", id: "temp", p: { vis: false, ty: "label", id: "zzz" } });
    expect(s.widgets.get("temp")!.ty).toBe("gauge");
    expect(s.widgets.get("temp")!.id).toBe("temp");
    expect(layout).toBe(1);
    s.apply({ t: "prop", id: "nope", p: { lbl: "x" } });
    expect(s.widgets.has("nope")).toBe(false);
  });
  it("keeps the current page across ui resends when it still exists", () => {
    const s = fresh();
    s.apply(showcase);
    s.setPage("setup");
    s.apply(showcase);
    expect(s.page).toBe("setup");
    s.apply({ t: "ui", rev: 8, w: [{ id: "only", ty: "page" }] });
    expect(s.page).toBe("only");
  });
});

describe("values", () => {
  it("stores upd values and notifies per widget", () => {
    const s = fresh();
    let temp = 0, pump = 0;
    s.subscribe("v:temp", () => temp++);
    s.subscribe("v:pump", () => pump++);
    s.apply({ t: "upd", v: { temp: 21.5, pump: true } });
    s.apply({ t: "upd", v: { temp: 22 } });
    expect(s.values.get("temp")).toBe(22);
    expect(s.values.get("pump")).toBe(true);
    expect(temp).toBe(2); expect(pump).toBe(1);
  });
});

describe("chart ring buffers", () => {
  it("rebases uptime timestamps on the hello and keeps epoch ones", () => {
    const s = fresh(1_000_000);
    s.apply({ t: "ui", rev: 1, w: [{ id: "c", ty: "chart", series: [{ id: "a" }], win: 10 }] });
    s.apply({ t: "pts", id: "c", s: "a", p: [[5000, 1], [6000, 2]] });
    expect(s.charts.get("c")!.get("a")).toEqual([[1_000_000, 1], [1_001_000, 2]]);
    s.apply({ t: "pts", id: "c", s: "a", p: [[1728700000123, 3]] });
    expect(s.charts.get("c")!.get("a")!.pop()).toEqual([1728700000123, 3]);
  });
  it("trims to win seconds and drops out-of-order points", () => {
    const s = fresh(0);
    s.apply(hello(0));
    s.apply({ t: "ui", rev: 1, w: [{ id: "c", ty: "chart", series: [{ id: "a" }, { id: "b" }], win: 10 }] });
    s.apply({ t: "pts", id: "c", s: "a", p: Array.from({ length: 30 }, (_, i) => [i * 1000, i] as [number, number]) });
    const a = s.charts.get("c")!.get("a")!;
    expect(a.length).toBe(11);
    expect(a[0][0]).toBe(19_000);
    s.apply({ t: "pts", id: "c", s: "a", p: [[1000, 99]] });
    expect(a.length).toBe(11);
    s.apply({ t: "pts", id: "c", s: "b", p: [[40_000, 1]] });
    expect(s.charts.get("c")!.get("a")!.length).toBe(0);
  });
  it("buffers points for charts not yet in the ui", () => {
    const s = fresh();
    s.apply({ t: "pts", id: "x", s: "a", p: [[1, 1]] });
    expect(s.charts.get("x")!.get("a")!.length).toBe(1);
  });
});

describe("logs", () => {
  it("caps widget logs, dedupes replays, routes untargeted lines to the console", () => {
    const s = fresh();
    s.apply({ t: "ui", rev: 1, w: [{ id: "term", ty: "log", cap: 10 }] });
    for (let i = 0; i < 25; i++) s.apply({ t: "log", id: "term", msg: "line " + i, ts: i });
    const lines = s.logs.get("term")!;
    expect(lines.length).toBe(10);
    expect(lines[0].msg).toBe("line 15");
    s.apply({ t: "log", id: "term", msg: "line 24", ts: 24 });
    expect(lines.length).toBe(10);
    s.apply({ t: "log", msg: "boot ok" });
    expect(s.console[0].msg).toBe("boot ok");
    s.apply({ t: "log", id: "term", msg: "red", c: "#ff0000" });
    expect(lines[lines.length - 1]).toMatchObject({ msg: "red", c: "#ff0000" });
  });
});

describe("dialogs and toasts", () => {
  it("queues dialogs in order, closes by id, ignores duplicates", () => {
    const s = fresh();
    s.apply({ t: "dlg", id: "d1", kind: "confirm", msg: "Erase?" });
    s.apply({ t: "dlg", id: "d2", kind: "prompt", msg: "Name", def: "Boiler", timeout: 120 });
    s.apply({ t: "dlg", id: "d1", kind: "confirm", msg: "again" });
    expect(s.dialogs.map((d) => d.id)).toEqual(["d1", "d2"]);
    expect(s.dialogs[0].timeout).toBe(60);
    s.apply({ t: "dlg", id: "d1", close: true });
    expect(s.dialogs.map((d) => d.id)).toEqual(["d2"]);
    expect(s.dialogs[0]).toMatchObject({ kind: "prompt", def: "Boiler", timeout: 120 });
  });
  it("turns toast and err messages into toasts", () => {
    const s = fresh();
    s.apply({ t: "toast", lvl: "warn", msg: "Overheating" });
    s.apply({ t: "err", code: 7, msg: "out of range", ref: "set" });
    expect(s.toasts.map((t) => t.lvl)).toEqual(["warn", "err"]);
    expect(s.toasts[1].msg).toContain("out of range");
    s.removeToast(s.toasts[0].id);
    expect(s.toasts.length).toBe(1);
  });
});

describe("sys", () => {
  it("records info, wifi status and scan results", () => {
    const s = fresh();
    s.apply({ t: "sys", cmd: "info", chip: "ESP32", fw: "1.0", heap: 1, up: 2 });
    s.apply({ t: "sys", cmd: "wifi.status", st: "connected", ip: "1.2.3.4" });
    s.apply({ t: "sys", cmd: "wifi.scan", ap: [{ ssid: "Home", rssi: -55, enc: true }] });
    expect(s.sysInfo?.chip).toBe("ESP32");
    expect(s.wifi?.ip).toBe("1.2.3.4");
    expect(s.wifiScan).toHaveLength(1);
    expect(s.hasCap("chart")).toBe(true);
    expect(s.hasCap("ota")).toBe(false);
  });
});
