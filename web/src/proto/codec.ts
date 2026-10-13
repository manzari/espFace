import type { D2C, Value } from "./types";

// Parses one device frame; returns null for anything that is not a JSON object with a string "t".
export function decode(text: string): D2C | null {
  let m: unknown;
  try { m = JSON.parse(text); } catch { return null; }
  if (!m || typeof m !== "object" || Array.isArray(m) || typeof (m as { t?: unknown }).t !== "string") return null;
  return m as D2C;
}

export function encode(msg: object): string { return JSON.stringify(msg); }

export const c2d = {
  hello: (tok?: string) => ({ t: "hello", v: 1, client: "web", ...(tok ? { tok } : {}) }),
  auth: (mac: string) => ({ t: "auth", mac }),
  time: (unix = Math.floor(Date.now() / 1000), tz = -new Date().getTimezoneOffset()) => ({ t: "time", unix, tz }),
  set: (id: string, v: Value) => ({ t: "set", id, v }),
  ev: (id: string, v?: 0 | 1 | "u" | "d" | "l" | "r" | "c") => ({ t: "ev", id, ...(v !== undefined ? { v } : {}) }),
  dlg: (id: string, ok: boolean, v?: string) => ({ t: "dlg", id, ok, ...(ok && v !== undefined ? { v } : {}) }),
  page: (id: string) => ({ t: "page", id }),
  sys: (cmd: string, extra: Record<string, unknown> = {}) => ({ t: "sys", cmd, ...extra }),
};
