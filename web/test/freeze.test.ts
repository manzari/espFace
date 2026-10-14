// Renderer v1 freeze gate (web/RENDERER-VERSIONING.md): /r/1/ must keep handling every protocol v1 message and widget type.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { c2d, decode } from "../src/proto/codec";
import type { D2C } from "../src/proto/types";
import { Store } from "../src/store";
import { registry } from "../src/widgets";
import { loadVectors, protoDir } from "./vectors";

const LAYOUT = ["group", "page", "row"];
const spec = readFileSync(join(protoDir, "PROTOCOL.md"), "utf8");
const typesTable = spec.slice(spec.indexOf("### 5.2 Types"), spec.indexOf("Defaults:"));
const widgetTypes = [...typesTable.matchAll(/^\| `([a-z]+)` \|/gm)].map((m) => m[1]);
const schema = JSON.parse(readFileSync(join(protoDir, "schema", "v1", "message.schema.json"), "utf8")) as { $defs: Record<string, { properties?: { t?: { const?: string } } }> };
const msgTypes = (dir: "c2d" | "d2c") => Object.entries(schema.$defs).filter(([k]) => k.startsWith(dir + "_")).map(([, d]) => d.properties?.t?.const).filter((t): t is string => !!t);
const vectors = loadVectors();

describe("protocol v1 widget types", () => {
  it("the spec table lists all 30 types", () => expect(widgetTypes).toHaveLength(30));
  for (const ty of widgetTypes.filter((t) => !LAYOUT.includes(t))) it(`${ty} has a renderer`, () => expect(registry[ty]).toBeTypeOf("function"));
  it("layout types build pages, groups and rows", () => {
    const s = new Store();
    s.apply({ t: "ui", rev: 1, w: [{ id: "p", ty: "page" }, { id: "g", ty: "group", page: "p" }, { id: "r", ty: "row", grp: "g" }, { id: "a", ty: "label", grp: "g", row: "r" }, { id: "b", ty: "label", grp: "g", row: "r" }] } as D2C);
    const block = s.pages()[0].blocks[0];
    expect(block).toMatchObject({ kind: "group", id: "g", items: [{ kind: "row", id: "r", items: ["a", "b"] }] });
  });
  it("every widget in a valid ui vector is renderable or a layout type", () => {
    const tys = vectors.filter((v) => v.dir === "d2c" && v.valid !== false && v.msg.t === "ui").flatMap((v) => (v.msg.w as { ty: string }[]).map((w) => w.ty));
    for (const ty of tys.filter((t) => widgetTypes.includes(t))) expect(registry[ty] ?? (LAYOUT.includes(ty) ? true : undefined)).toBeTruthy();
  });
});

describe("protocol v1 messages", () => {
  const d2c = msgTypes("d2c");
  it("schema defines the v1 message sets", () => {
    expect(d2c.sort()).toEqual(["auth", "dlg", "err", "hello", "log", "prop", "pts", "sys", "toast", "ui", "upd"]);
    expect(msgTypes("c2d").sort()).toEqual(["auth", "dlg", "ev", "hello", "page", "set", "sys", "time"]);
  });
  it("the client can build every c2d type", () => {
    const built = [c2d.hello(), c2d.auth("0".repeat(64)), c2d.time(), c2d.set("x", 1), c2d.ev("x"), c2d.dlg("x", true), c2d.page("x"), c2d.sys("info")].map((m) => m.t);
    expect(built.sort()).toEqual(msgTypes("c2d").sort());
  });
  for (const t of d2c) {
    it(`d2c ${t}: a vector exists, decodes and is handled`, () => {
      const vs = vectors.filter((v) => v.dir === "d2c" && v.valid !== false && v.msg.t === t);
      expect(vs.length).toBeGreaterThan(0);
      let emitted = 0;
      for (const v of vs) {
        const m = decode(JSON.stringify(v.msg));
        expect(m?.t).toBe(t);
        const s = new Store();
        s.apply({ t: "hello", v: 1, name: "x", id: "a1b2c3", auth: "none", ok: true, up: 0, caps: ["chart"] });
        s.apply(vectors.find((x) => x.name === "ui full showcase")!.msg as unknown as D2C);
        const orig = s.emit.bind(s);
        s.emit = (k: string) => { emitted++; orig(k); };
        expect(() => s.apply(m!)).not.toThrow();
      }
      // auth replies are handled by Session.onAuth, not the store; some vectors (empty upd, dlg close) are no-ops
      if (t !== "auth") expect(emitted).toBeGreaterThan(0);
    });
  }
});
