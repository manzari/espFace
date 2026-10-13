import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import { md5hex } from "../src/proto/md5";
import { CHUNK, chunks, compareVersions, pickRelease, pushImage, releaseUrl, type OtaSocket } from "../src/sys/ota";
import { Store } from "../src/store";

describe("md5", () => {
  it("matches RFC 1321 vectors and Node for odd sizes", () => {
    const enc = new TextEncoder();
    expect(md5hex(new Uint8Array(0))).toBe("d41d8cd98f00b204e9800998ecf8427e");
    expect(md5hex(enc.encode("abc"))).toBe("900150983cd24fb0d6963f7d28e17f72");
    expect(md5hex(enc.encode("The quick brown fox jumps over the lazy dog"))).toBe("9e107d9d372bb6826bd81d3542a419d6");
    for (const n of [55, 56, 63, 64, 65, 1000, 4096 * 3 + 17]) {
      const buf = new Uint8Array(n).map((_, i) => (i * 31 + 7) & 255);
      expect(md5hex(buf)).toBe(createHash("md5").update(buf).digest("hex"));
    }
  });
});

describe("chunker", () => {
  it("splits into 4096-byte frames in order, last one short", () => {
    const data = new Uint8Array(CHUNK * 2 + 100).map((_, i) => i & 255);
    const parts = [...chunks(data)];
    expect(parts.map((p) => p.length)).toEqual([CHUNK, CHUNK, 100]);
    expect(parts[2][0]).toBe((CHUNK * 2) & 255);
    expect([...chunks(new Uint8Array(0))]).toEqual([]);
    expect([...chunks(data, 1000)].length).toBe(9);
  });
});

function fakeSocket(opts: { fail?: number; drain?: number } = {}) {
  const sent: Uint8Array[] = [];
  let buffered = 0;
  const sock: OtaSocket & { sent: Uint8Array[]; buffered: () => number } = {
    sent,
    buffered: () => buffered,
    sendBinary(b) { if (opts.fail !== undefined && sent.length >= opts.fail) return false; sent.push(new Uint8Array(b)); buffered += b.length; return true; },
    bufferedAmount() { return buffered; },
  };
  const sleep = async () => { buffered = Math.max(0, buffered - (opts.drain ?? 1 << 30)); };
  return { sock, sleep };
}

describe("pushImage", () => {
  it("sends every byte in order and reports progress", async () => {
    const data = new Uint8Array(10000).map((_, i) => (i * 7) & 255);
    const { sock, sleep } = fakeSocket();
    const progress: number[] = [];
    const n = await pushImage(sock, data, { sleep, onProgress: (s) => progress.push(s) });
    expect(n).toBe(10000);
    expect(progress).toEqual([4096, 8192, 10000]);
    const joined = new Uint8Array(10000);
    let off = 0;
    for (const c of sock.sent) { joined.set(c, off); off += c.length; }
    expect(joined).toEqual(data);
  });
  it("waits for the socket to drain before exceeding the high-water mark", async () => {
    const data = new Uint8Array(CHUNK * 20);
    const { sock, sleep } = fakeSocket({ drain: CHUNK * 4 });
    let waits = 0;
    const slept = async () => { waits++; await sleep(); };
    await pushImage(sock, data, { sleep: slept, highWater: CHUNK * 4 });
    expect(sock.sent.length).toBe(20);
    expect(waits).toBeGreaterThan(0);
    expect(sock.buffered()).toBeLessThanOrEqual(CHUNK * 5);
  });
  it("rejects when the socket closes or the user aborts", async () => {
    const data = new Uint8Array(CHUNK * 3);
    const { sock, sleep } = fakeSocket({ fail: 2 });
    await expect(pushImage(sock, data, { sleep })).rejects.toThrow("connection lost");
    expect(sock.sent.length).toBe(2);
    const s2 = fakeSocket();
    let n = 0;
    await expect(pushImage(s2.sock, data, { sleep: s2.sleep, aborted: () => ++n > 1 })).rejects.toThrow("aborted");
    expect(s2.sock.sent.length).toBe(1);
  });
});

describe("release check", () => {
  it("compares versions loosely", () => {
    expect(compareVersions("1.2.3", "1.2.3")).toBe(0);
    expect(compareVersions("v1.2.3", "1.2.3")).toBe(0);
    expect(compareVersions("1.10.0", "1.9.9")).toBe(1);
    expect(compareVersions("1.2", "1.2.0")).toBe(0);
    expect(compareVersions("1.2.0-beta", "1.2.0")).toBe(-1);
    expect(compareVersions("1.2.0", "1.2.0-rc1")).toBe(1);
    expect(compareVersions("2.0.0", "1.99.99")).toBe(1);
    expect(compareVersions("0.1.0", "0.0.1-fake")).toBe(1);
  });
  it("picks the first .bin asset", () => {
    expect(pickRelease({ tag_name: "v1.3.0", html_url: "https://github.com/o/r/releases/tag/v1.3.0", assets: [{ name: "notes.txt", browser_download_url: "x" }, { name: "fw-esp32.bin", browser_download_url: "https://dl/fw-esp32.bin" }, { name: "fw-s3.bin", browser_download_url: "https://dl/fw-s3.bin" }] }))
      .toEqual({ version: "v1.3.0", url: "https://dl/fw-esp32.bin", asset: "fw-esp32.bin", page: "https://github.com/o/r/releases/tag/v1.3.0" });
    expect(pickRelease({ tag_name: "v2", assets: [] })).toEqual({ version: "v2", url: null, asset: null, page: undefined });
    expect(pickRelease({})).toBeNull();
    expect(releaseUrl("owner/repo")).toBe("https://api.github.com/repos/owner/repo/releases/latest");
  });
});

describe("store OTA state", () => {
  it("tracks begin, progress, done, errors and a dropped connection", () => {
    const s = new Store();
    s.apply({ t: "sys", cmd: "ota.begin", ok: true });
    expect(s.ota).toEqual({ pct: 0 });
    s.apply({ t: "sys", cmd: "ota.progress", pct: 42 });
    expect(s.ota?.pct).toBe(42);
    s.apply({ t: "sys", cmd: "ota.done", ok: false, msg: "md5 mismatch" });
    expect(s.ota).toEqual({ pct: 42, done: true, ok: false, msg: "md5 mismatch" });
    s.apply({ t: "sys", cmd: "ota.begin", ok: true });
    s.apply({ t: "sys", cmd: "ota.progress", pct: 100 });
    s.apply({ t: "sys", cmd: "ota.done", ok: true });
    expect(s.ota).toEqual({ pct: 100, done: true, ok: true, msg: undefined });
    s.reset();
    expect(s.ota?.ok).toBe(true);   // survives the reboot disconnect so the page can say so
    s.apply({ t: "sys", cmd: "ota.begin", ok: true });
    s.apply({ t: "err", code: 9, msg: "ota in progress", ref: "ota.begin" });
    expect(s.ota).toEqual({ pct: 0, done: true, ok: false, msg: "ota in progress" });
    s.apply({ t: "sys", cmd: "ota.url", ok: true });
    s.apply({ t: "sys", cmd: "ota.progress", pct: 20 });
    s.reset();
    expect(s.ota).toEqual({ pct: 20, done: true, ok: false, msg: "connection lost" });
    s.apply({ t: "sys", cmd: "ota.abort", ok: true });
    expect(s.ota).toBeNull();
  });
});
