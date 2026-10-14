// Generates reference/{espface,ui,widgetref,propref}.md from firmware/src/Face.h, firmware/src/ui/Ui.h and the
// firmware README tables. Descriptions and examples come from api-notes.json; anything the notes do not cover
// still gets its signature, the header comment and an auto-generated example, so new methods never go missing.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const notes = JSON.parse(readFileSync(join(here, "api-notes.json"), "utf8"));
const out = join(here, "..", "reference");
mkdirSync(out, { recursive: true });

const faceH = readFileSync(join(root, "firmware", "src", "Face.h"), "utf8");
const uiH = readFileSync(join(root, "firmware", "src", "ui", "Ui.h"), "utf8");
const readme = readFileSync(join(root, "firmware", "README.md"), "utf8");

// ---- header parsing -----------------------------------------------------
function classBody(src, name) {
  const m = new RegExp(`class ${name}\\b[^;{]*\\{`).exec(src);
  if (!m) throw new Error(`class ${name} not found`);
  let depth = 1, i = m.index + m[0].length, start = i;
  for (; i < src.length && depth; i++) { if (src[i] === "{") depth++; else if (src[i] === "}") depth--; }
  return src.slice(start, i - 1);
}

// Public method declarations: one per line (inline bodies may continue on later lines, which are skipped).
function methods(body, { stopAt } = {}) {
  const lines = body.split("\n");
  const res = [];
  let pub = false, depth = 0, pending = [], stopped = false;
  for (const raw of lines) {
    const line = raw.trim();
    if (stopAt && line.startsWith(stopAt)) stopped = true;
    if (/^public:/.test(line)) { pub = true; continue; }
    if (/^(private|protected):/.test(line)) { pub = false; continue; }
    if (depth > 0) { depth += count(line, "{") - count(line, "}"); continue; }
    if (!pub || stopped) continue;
    if (line.startsWith("//")) { pending.push(line.replace(/^\/\/\s?/, "")); continue; }
    if (!line) { pending = []; continue; }
    const d = splitDecl(line);
    if (d && !d.ctor) {
      const { ret, name, args, rest } = d;
      if (name.startsWith("~") || name.startsWith("operator")) { pending = []; continue; }
      const m2 = /^\s*(const)?\s*(?:=\s*0)?\s*(\{.*|;)?\s*(\/\/\s*(.*))?$/.exec(rest);
      const tail = m2?.[2], trailing = m2?.[4];
      depth = tail && tail.startsWith("{") ? count(tail, "{") - count(tail, "}") : 0;
      res.push({ name, ret, args: splitArgs(args), const: !!m2?.[1], comment: [...pending, trailing ?? ""].filter(Boolean).join(" ").trim(), template: /^template/.test(line) });
      pending = [];
    } else if (d) {
      const { name, args, rest } = d;
      const m2 = /^\s*(:[^{]*)?(\{.*|;)?\s*(\/\/\s*(.*))?$/.exec(rest);
      const tail = m2?.[2], trailing = m2?.[4];
      depth = tail && tail.startsWith("{") ? count(tail, "{") - count(tail, "}") : 0;
      res.push({ name, ret: "", args: splitArgs(args), ctor: true, comment: [...pending, trailing ?? ""].filter(Boolean).join(" ").trim() });
      pending = [];
    } else {
      // field or using-declaration: an opening brace still needs tracking
      depth = count(line, "{") - count(line, "}");
      if (depth < 0) depth = 0;
      pending = [];
    }
  }
  return res;
}

const count = (s, ch) => s.split(ch).length - 1;

// `ret name(args) rest` with balanced parentheses in args (std::function<void(int)> etc.).
function splitDecl(line) {
  const head = /^(?:template\s*<[^>]*>\s*)?(?:(?:explicit|virtual|static)\s+)*(?:([\w:<>&*, ]+?)\s+)?([~\w]+)\s*\(/.exec(line);
  if (!head) return null;
  const [, ret, name] = head;
  let depth = 1, i = head[0].length;
  const start = i;
  for (; i < line.length && depth; i++) { if (line[i] === "(") depth++; else if (line[i] === ")") depth--; }
  if (depth) return null;
  const args = line.slice(start, i - 1);
  const rest = line.slice(i);
  if (!ret) return /^[A-Z]/.test(name) ? { ctor: true, name, args, rest } : null;
  if (/^(return|if|for|while|using)$/.test(ret.trim())) return null;
  return { ret: ret.trim(), name, args, rest };
}


function splitArgs(s) {
  if (!s.trim()) return [];
  const parts = [];
  let depth = 0, cur = "";
  for (const ch of s) {
    if (ch === "<" || ch === "(") depth++;
    if (ch === ">" || ch === ")") depth--;
    if (ch === "," && depth === 0) { parts.push(cur); cur = ""; } else cur += ch;
  }
  parts.push(cur);
  return parts.map((p) => {
    const m = /^\s*(.*?)\s*([\w]+)\s*(?:=\s*(.+))?\s*$/.exec(p.trim());
    if (!m) return { type: p.trim(), name: "", def: undefined };
    return { type: m[1].trim(), name: m[2], def: m[3]?.trim() };
  });
}

// ---- example synthesis --------------------------------------------------
const PLACEHOLDER = { id: '"temp"', lbl: '"Temperature"', name: '"Boiler"', pin: '"1234"', host: '"https://your.host"', server: '"https://ntfy.sh"', topic: '"alerts"', token: "nullptr", url: '"https://example.com/fw.bin"', src: '"http://192.168.1.60/cam.jpg"', msg: '"Erase everything?"', text: '"Instructions"', title: '"Boiler"', color: '"#ff0000"', hex: '"#ff0000"', unit: '"°C"', re: '"^[A-Za-z ]*$"', fmt: '"%.1f"', mode: '"time"', style: '"seg"', align: '"right"', on: '"ON"', off: '"OFF"', def: '"Boiler"', tz: '"CET-1CEST,M3.5.0,M10.5.0/3"', pem: "CA_CERT", p: '"Home"', i: '"thermostat"', v: '"1.2.0"', r: '"owner/repo"', a: '"Boiler controller"', chart: '"tchart"', series: '"temp"', chartId: '"tchart"', seriesId: '"temp"', logId: '"term"', rowsJson: '"[[\\"Kitchen\\",21.5],[\\"Bath\\",23]]"', pointsJson: '"[[52.52,13.4,\\"Home\\"]]"', opts: '{"Off", "Auto", "Manual"}' };

function argValue(a, ctx) {
  if (a.def !== undefined && a.def !== "nullptr" && a.def !== "0") return a.def;
  if (PLACEHOLDER[a.name]) return PLACEHOLDER[a.name];
  const t = a.type.replace(/\s+/g, " ");
  if (/std::function<void\(\)>/.test(t)) return "[] { /* ... */ }";
  if (/std::function<void\(const ClientInfo&\)>/.test(t)) return "[](const ClientInfo& c) { /* ... */ }";
  if (/std::function<void\(RebootReason\)>/.test(t)) return "[](RebootReason r) { saveState(); }";
  if (/DialogFn/.test(t)) return "[](bool ok, const Str& text) { /* ... */ }";
  if (/EventFn/.test(t)) return "[](int v) { /* 1 press, 0 release */ }";
  if (/MoveFn/.test(t)) return "[](int x, int y) { /* ... */ }";
  if (/vector<const char\*>/.test(t)) return '{"A", "B", "C"}';
  if (/Stream&/.test(t)) return "Serial";
  if (/Print\*/.test(t)) return "&Serial";
  if (/Ntfy\b/.test(t)) return "Ntfy::High";
  if (/const Value&/.test(t)) return "Value::ofFloat(21.5)";
  if (/^bool&$/.test(t)) return "pumpOn";
  if (/^int&$/.test(t)) return "cycles";
  if (/^float&$/.test(t)) return "target";
  if (/^Str&$/.test(t)) return "note";
  if (/^bool$/.test(t)) return "true";
  if (/const char\*/.test(t)) return `"${a.name}"`;
  if (/const String&/.test(t)) return 'String("text")';
  if (/uint64_t/.test(t)) return "0";
  if (/uint32_t|uint16_t|uint8_t|int|float|double/.test(t)) return ctx?.num?.[a.name] ?? (a.name === "min" ? "0" : a.name === "max" ? "100" : a.name === "step" ? "1" : a.name === "x" ? "10" : a.name === "y" ? "-10" : a.name === "ms" ? "50" : a.name === "zoom" ? "12" : "1");
  return a.name;
}

function argsText(m, ctx) { return m.args.map((a) => argValue(a, ctx)).join(", "); }

function autoExample(cls, m) {
  const call = `${m.name}(${argsText(m)})`;
  switch (cls) {
    case "EspFace": return `face.${call};`;
    case "Ui": return `face.ui().${call};`;
    case "WidgetRef": return `ui.slider("target", "Target", 20, 90).${call};`;
    case "PropRef": return `ui.prop("temp").${call};   // sent when the PropRef goes out of scope`;
    default: return call;
  }
}

function signature(m) {
  const args = m.args.map((a) => `${a.type} ${a.name}${a.def !== undefined ? ` = ${a.def}` : ""}`).join(", ");
  return `${m.template ? "template <class F> " : ""}${m.ret ? m.ret + " " : ""}${m.name}(${args})${m.const ? " const" : ""}`;
}

// ---- rendering ----------------------------------------------------------
function render(cls, ms, intro, order) {
  const byGroup = new Map();
  const seen = new Set();
  for (const m of ms) {
    const key = `${cls}::${m.name}`;
    const n = notes.methods[key] ?? {};
    if (n.hide) continue;
    const group = n.group ?? "Other";
    if (!byGroup.has(group)) byGroup.set(group, []);
    const dup = seen.has(key);
    seen.add(key);
    byGroup.get(group).push({ m, n, dup });
  }
  let md = `# ${notes.classes[cls].title}\n\n::: info Generated\nThis page is generated by \`docs/site/scripts/gen-api.mjs\` from \`firmware/src/${cls === "EspFace" ? "Face.h" : "ui/Ui.h"}\`; descriptions and examples live in \`docs/site/scripts/api-notes.json\`.\n:::\n\n${intro}\n`;
  const groups = [...byGroup.keys()].sort((a, b) => (order.indexOf(a) === -1 ? 99 : order.indexOf(a)) - (order.indexOf(b) === -1 ? 99 : order.indexOf(b)));
  for (const g of groups) {
    md += `\n## ${g}\n`;
    if (notes.groups?.[`${cls}::${g}`]) md += `\n${notes.groups[`${cls}::${g}`]}\n`;
    // overloads share one section
    const byName = new Map();
    for (const e of byGroup.get(g)) { if (!byName.has(e.m.name)) byName.set(e.m.name, []); byName.get(e.m.name).push(e); }
    for (const [name, entries] of byName) {
      const { n } = entries[0];
      md += `\n### \`${name}\`\n\n`;
      md += "```cpp\n" + entries.map(({ m }) => signature(m)).join("\n") + "\n```\n\n";
      const desc = n.desc ?? entries.map(({ m }) => m.comment).find(Boolean) ?? "";
      if (desc) md += `${desc}\n\n`;
      const args = entries[0].m.args.filter((a) => a.name);
      if (args.length && (n.args || args.some((a) => a.def !== undefined))) {
        md += "| Argument | Type | Default | Meaning |\n|---|---|---|---|\n";
        for (const a of args) md += `| \`${a.name}\` | \`${a.type}\` | ${a.def !== undefined ? "`" + a.def + "`" : "–"} | ${n.args?.[a.name] ?? ""} |\n`;
        md += "\n";
      }
      md += "```cpp\n" + (n.example ?? autoExample(cls, entries[0].m)) + "\n```\n";
    }
  }
  return md;
}

const face = methods(classBody(faceH, "EspFace"));
const widgetRef = methods(classBody(uiH, "WidgetRef"));
const propRef = methods(classBody(uiH, "PropRef"));
const ui = methods(classBody(uiH, "Ui"), { stopAt: "// ---- used by Core" });

const builderTable = (() => {
  const m = /## Builder \(`face\.ui\(\)`\)\n([\s\S]*?)\n## Runtime/.exec(readme);
  return m ? m[1].trim() : "";
})();
const runtimeTable = (() => {
  const m = /## Runtime\n([\s\S]*?)\n## System features/.exec(readme);
  return m ? m[1].trim() : "";
})();

const check = (list, must, where) => { for (const n of must) if (!list.some((m) => m.name === n)) throw new Error(`${where}: expected method ${n} not found`); };
check(face, ["begin", "loop", "setPin", "enableOta", "ui", "set", "push", "notify"], "Face.h");
check(ui, ["page", "gauge", "chart", "rebuild", "confirm", "prompt", "push", "set"], "Ui.h");
check(widgetRef, ["group", "row", "persist", "onChange", "onClick", "bind"], "WidgetRef");
check(propRef, ["label", "visible", "options"], "PropRef");

writeFileSync(join(out, "espface.md"), render("EspFace", face, notes.classes.EspFace.intro, notes.classes.EspFace.order));
writeFileSync(join(out, "ui.md"), render("Ui", ui, notes.classes.Ui.intro + "\n\n" + builderTable + "\n\n" + runtimeTable.replace(/^\| Call/, "| Runtime call"), notes.classes.Ui.order));
writeFileSync(join(out, "widgetref.md"), render("WidgetRef", widgetRef, notes.classes.WidgetRef.intro, notes.classes.WidgetRef.order));
writeFileSync(join(out, "propref.md"), render("PropRef", propRef, notes.classes.PropRef.intro, notes.classes.PropRef.order));
console.log(`api reference: EspFace ${face.length}, Ui ${ui.length}, WidgetRef ${widgetRef.length}, PropRef ${propRef.length} methods`);
