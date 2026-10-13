// Prints raw and gzipped sizes of the bundle and fails when the budget (80 KB gzipped) is exceeded.
import { readFileSync, statSync } from "node:fs";
import { gzipSync } from "node:zlib";

const BUDGET = 80 * 1024;
let total = 0;
for (const f of ["dist/r/1/app.js", "dist/r/1/app.css"]) {
  const gz = gzipSync(readFileSync(f), { level: 9 }).length;
  total += gz;
  console.log(`${f}: ${statSync(f).size} bytes, ${gz} gzipped`);
}
console.log(`total gzipped: ${total} bytes (${(total / 1024).toFixed(1)} KB, budget ${BUDGET / 1024} KB)`);
if (total > BUDGET) { console.error("bundle over budget"); process.exit(1); }
