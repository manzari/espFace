// Renderer v1 freeze gate on the built bundle: frozen paths exist and every v1 widget/message type is still in app.js.
import { existsSync, readFileSync } from "node:fs";

const spec = readFileSync("../protocol/PROTOCOL.md", "utf8");
const table = spec.slice(spec.indexOf("### 5.2 Types"), spec.indexOf("Defaults:"));
const widgets = [...table.matchAll(/^\| `([a-z]+)` \|/gm)].map((m) => m[1]);
const schema = JSON.parse(readFileSync("../protocol/schema/v1/message.schema.json", "utf8"));
const msgs = Object.entries(schema.$defs).filter(([k]) => /^(c2d|d2c)_/.test(k)).map(([, d]) => d.properties?.t?.const).filter(Boolean);
const fail = [];
for (const f of ["dist/r/1/app.js", "dist/r/1/app.css", "dist/connect/index.html", "dist/index.html"]) if (!existsSync(f)) fail.push(`missing ${f}`);
const js = existsSync("dist/r/1/app.js") ? readFileSync("dist/r/1/app.js", "utf8") : "";
const has = (s) => js.includes(`"${s}"`) || js.includes(`${s}:`) || js.includes(`'${s}'`);
if (widgets.length !== 30) fail.push(`expected 30 widget types in PROTOCOL.md, found ${widgets.length}`);
for (const w of widgets) if (!has(w)) fail.push(`widget type ${w} not found in app.js`);
for (const m of new Set(msgs)) if (!has(m)) fail.push(`message type ${m} not found in app.js`);
if (fail.length) { console.error("renderer v1 freeze check failed:\n  " + fail.join("\n  ")); process.exit(1); }
console.log(`renderer v1 freeze check OK: ${widgets.length} widget types, ${new Set(msgs).size} message types, frozen paths present`);
