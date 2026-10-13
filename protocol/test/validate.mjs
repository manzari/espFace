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

if (process.argv[1] === fileURLToPath(import.meta.url)) run();
