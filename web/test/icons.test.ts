import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import spec from "../src/icons.json";
import { FALLBACK, P } from "../src/icons-paths";

// The web subset (icons.json -> generated paths) and the app's icon map must name the same icons.
describe("shared icon subset", () => {
  const names = Object.keys(spec.icons).sort();
  it("generated paths cover every name in icons.json", () => {
    expect(Object.keys(P).sort()).toEqual(names);
    for (const n of names) expect(P[n]).toMatch(/^[Mm]/);
    expect(FALLBACK).toMatch(/^[Mm]/);
  });
  it("the Flutter app maps exactly the same names", () => {
    const dart = readFileSync(join(__dirname, "..", "..", "apps", "mobile", "lib", "features", "render", "icons.dart"), "utf8");
    const appNames = [...dart.matchAll(/'([a-z_0-9]+)': Icons\.[a-z_0-9]+/g)].map((m) => m[1]).sort();
    expect(appNames).toEqual(names);
    expect(dart).toContain(`Icons.${spec.fallback}`);
  });
  it("names are valid icon identifiers", () => {
    for (const n of names) expect(n).toMatch(/^[a-z][a-z0-9_]*$/);
  });
});
