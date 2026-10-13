// OTA push helpers: chunking with socket backpressure, and the GitHub release check. Pure, no DOM.
export const CHUNK = 4096;
export const HIGH_WATER = 16 * CHUNK;

export function* chunks(data: Uint8Array, size = CHUNK): Generator<Uint8Array> {
  for (let off = 0; off < data.length; off += size) yield data.subarray(off, Math.min(off + size, data.length));
}

export interface OtaSocket { sendBinary(b: Uint8Array): boolean; bufferedAmount(): number }
export interface PushOptions { chunk?: number; highWater?: number; onProgress?: (sent: number, total: number) => void; aborted?: () => boolean; sleep?: (ms: number) => Promise<void> }

// Sends every chunk in order; waits while bufferedAmount is above the high-water mark. Rejects on a closed socket or abort.
export async function pushImage(sock: OtaSocket, data: Uint8Array, o: PushOptions = {}): Promise<number> {
  const sleep = o.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  const hw = o.highWater ?? HIGH_WATER;
  let sent = 0;
  for (const c of chunks(data, o.chunk ?? CHUNK)) {
    while (sock.bufferedAmount() > hw) { if (o.aborted?.()) throw new Error("aborted"); await sleep(20); }
    if (o.aborted?.()) throw new Error("aborted");
    if (!sock.sendBinary(c)) throw new Error("connection lost");
    sent += c.length;
    o.onProgress?.(sent, data.length);
  }
  return sent;
}

// Loose semver: "v1.2.3-beta" < "1.2.3" < "1.10.0". Non-numeric segments compare as strings.
export function compareVersions(a: string, b: string): number {
  const parse = (v: string) => { const m = /^v?([0-9A-Za-z.]*)(?:-([0-9A-Za-z.-]+))?/.exec(v.trim()) ?? ["", "", ""]; return { core: m[1].split(".").filter(Boolean), pre: m[2] ?? "" }; };
  const x = parse(a), y = parse(b);
  for (let i = 0; i < Math.max(x.core.length, y.core.length); i++) {
    const p = x.core[i] ?? "0", q = y.core[i] ?? "0";
    const np = Number(p), nq = Number(q);
    const c = Number.isFinite(np) && Number.isFinite(nq) ? Math.sign(np - nq) : p < q ? -1 : p > q ? 1 : 0;
    if (c) return c;
  }
  if (x.pre && !y.pre) return -1;
  if (!x.pre && y.pre) return 1;
  return x.pre < y.pre ? -1 : x.pre > y.pre ? 1 : 0;
}

export interface Release { tag_name?: string; name?: string; html_url?: string; assets?: { name: string; browser_download_url: string; size?: number }[] }
export interface ReleaseInfo { version: string; url: string | null; asset: string | null; page?: string }

export function pickRelease(r: Release): ReleaseInfo | null {
  const version = (r.tag_name ?? r.name ?? "").trim();
  if (!version) return null;
  const bin = (r.assets ?? []).find((a) => /\.bin$/i.test(a.name));
  return { version, url: bin?.browser_download_url ?? null, asset: bin?.name ?? null, page: r.html_url };
}

export const releaseUrl = (repo: string) => `https://api.github.com/repos/${repo}/releases/latest`;
