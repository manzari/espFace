import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

export const protoDir = join(__dirname, "..", "..", "protocol");

export interface Vector { name: string; dir: "c2d" | "d2c"; valid?: boolean; msg: Record<string, unknown>; hmac?: { pin: string; nonce: string; id: string } }

export function loadVectors(): Vector[] {
  const dir = join(protoDir, "vectors");
  return readdirSync(dir).filter((f) => f.endsWith(".json")).sort().flatMap((f) => JSON.parse(readFileSync(join(dir, f), "utf8")) as Vector[]);
}

// Same setup as protocol/test/validate.mjs.
export function makeValidator() {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  const schemaDir = join(protoDir, "schema", "v1");
  ajv.addSchema(JSON.parse(readFileSync(join(schemaDir, "widget.schema.json"), "utf8")));
  ajv.addSchema(JSON.parse(readFileSync(join(schemaDir, "message.schema.json"), "utf8")));
  const base = "https://espface.dev/schema/v1/message.schema.json";
  return { c2d: ajv.getSchema(base + "#/$defs/c2d")!, d2c: ajv.getSchema(base + "#/$defs/d2c")! };
}
