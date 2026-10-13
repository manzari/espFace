// Validates every vector in ../vectors against the v1 schema.
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { createHmac } from "node:crypto";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const schemaDir = join(root, "schema", "v1");
const vecDir = join(root, "vectors");

export function makeValidator() {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  ajv.addSchema(JSON.parse(readFileSync(join(schemaDir, "widget.schema.json"), "utf8")));
  ajv.addSchema(JSON.parse(readFileSync(join(schemaDir, "message.schema.json"), "utf8")));
  const base = "https://espface.dev/schema/v1/message.schema.json";
  return {
    c2d: ajv.getSchema(base + "#/$defs/c2d"),
    d2c: ajv.getSchema(base + "#/$defs/d2c"),
    widget: ajv.getSchema("https://espface.dev/schema/v1/widget.schema.json"),
  };
}

export function hmacPin(pin, nonceHex, deviceId) {
  return createHmac("sha256", Buffer.from(pin, "utf8")).update(nonceHex + deviceId).digest("hex");
}

function run() {
  const v = makeValidator();
  let pass = 0, fail = 0;
  for (const file of readdirSync(vecDir).filter((f) => f.endsWith(".json")).sort()) {
    const vectors = JSON.parse(readFileSync(join(vecDir, file), "utf8"));
    for (const vec of vectors) {
      const validate = v[vec.dir];
      if (!validate) { console.log(`FAIL ${file}: ${vec.name}: unknown dir ${vec.dir}`); fail++; continue; }
      const ok = validate(vec.msg);
      const expected = vec.valid !== false;
      let extra = "";
      if (vec.hmac) {
        const mac = hmacPin(vec.hmac.pin, vec.hmac.nonce, vec.hmac.id);
        if (mac !== vec.msg.mac) extra = ` hmac mismatch: computed ${mac}`;
      }
      if (ok === expected && !extra) pass++;
      else {
        fail++;
        console.log(`FAIL ${file}: ${vec.name} (expected ${expected ? "valid" : "invalid"}, got ${ok ? "valid" : "invalid"})${extra}`);
        if (!ok) console.log("  " + ajvErrors(validate.errors));
      }
    }
  }
  console.log(`${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

function ajvErrors(errs) {
  return (errs || []).slice(0, 6).map((e) => `${e.instancePath || "/"} ${e.message}`).join("; ");
}

// `node validate.mjs --d2c file.jsonl` validates one message per line (used for firmware test output).
function runFile(dir, file) {
  const v = makeValidator();
  const lines = readFileSync(file, "utf8").split("\n").filter((l) => l.trim());
  let fail = 0;
  for (const [i, line] of lines.entries()) {
    let m;
    try { m = JSON.parse(line); } catch (e) { fail++; console.log(`FAIL line ${i + 1}: not JSON: ${line.slice(0, 120)}`); continue; }
    if (!v[dir](m)) { fail++; console.log(`FAIL line ${i + 1}: ${ajvErrors(v[dir].errors)}\n  ${line.slice(0, 160)}`); }
  }
  console.log(`${lines.length - fail} of ${lines.length} ${dir} messages valid`);
  process.exit(fail ? 1 : 0);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const i = process.argv.findIndex((a) => a === "--c2d" || a === "--d2c");
  if (i > 0) runFile(process.argv[i].slice(2), process.argv[i + 1]); else run();
}
