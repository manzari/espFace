import { describe, expect, it } from "vitest";
import { c2d, decode, encode } from "../src/proto/codec";
import { hmacPin, hmacSha256, sha256 } from "../src/proto/hmac";
import { loadVectors, makeValidator } from "./vectors";

const v = makeValidator();
const valid = (m: object) => { const ok = v.c2d(m); if (!ok) throw new Error(JSON.stringify(v.c2d.errors?.slice(0, 3))); return ok; };

describe("c2d messages the client builds validate against the schema", () => {
  it("hello without and with token", () => {
    expect(valid(c2d.hello())).toBe(true);
    expect(valid(c2d.hello("0123456789abcdef0123456789abcdef"))).toBe(true);
    expect(c2d.hello()).not.toHaveProperty("tok");
  });
  it("auth", () => expect(valid(c2d.auth("0".repeat(64)))).toBe(true));
  it("time", () => { expect(valid(c2d.time())).toBe(true); expect(valid(c2d.time(1728700000, 120))).toBe(true); });
  it("set with every value kind", () => {
    expect(valid(c2d.set("pump", true))).toBe(true);
    expect(valid(c2d.set("target", 65.5))).toBe(true);
    expect(valid(c2d.set("note", "hello"))).toBe(true);
    expect(valid(c2d.set("joy", [-100, 100]))).toBe(true);
    expect(valid(c2d.set("col", 0xff8800))).toBe(true);
  });
  it("ev plain, hold and dpad", () => {
    expect(valid(c2d.ev("reset"))).toBe(true);
    expect(c2d.ev("reset")).not.toHaveProperty("v");
    expect(valid(c2d.ev("horn", 1))).toBe(true);
    expect(valid(c2d.ev("horn", 0))).toBe(true);
    for (const d of ["u", "d", "l", "r", "c"] as const) expect(valid(c2d.ev("pad", d))).toBe(true);
  });
  it("dlg answers", () => {
    expect(valid(c2d.dlg("d1", true))).toBe(true);
    expect(valid(c2d.dlg("d2", true, "Kitchen"))).toBe(true);
    expect(valid(c2d.dlg("d2", false, "ignored"))).toBe(true);
    expect(c2d.dlg("d2", false, "ignored")).not.toHaveProperty("v");
  });
  it("page", () => expect(valid(c2d.page("setup"))).toBe(true));
  it("sys commands used by the sys pages", () => {
    expect(valid(c2d.sys("info"))).toBe(true);
    expect(valid(c2d.sys("wifi.status"))).toBe(true);
    expect(valid(c2d.sys("wifi.scan"))).toBe(true);
    expect(valid(c2d.sys("wifi.set", { ssid: "Home", pass: "secret" }))).toBe(true);
    expect(valid(c2d.sys("reboot"))).toBe(true);
    expect(valid(c2d.sys("pin.set", { pin: "4321" }))).toBe(true);
    expect(valid(c2d.sys("pin.set", { pin: "" }))).toBe(true);
    expect(valid(c2d.sys("revoke"))).toBe(true);
    expect(valid(c2d.sys("ota.url", { url: "https://example.com/fw.bin" }))).toBe(true);
  });
  it("encode produces newline-free JSON", () => expect(encode(c2d.set("n", "a\nb"))).not.toContain("\n"));
});

describe("decode", () => {
  it("accepts objects with t and rejects the rest", () => {
    expect(decode('{"t":"upd","v":{}}')).toEqual({ t: "upd", v: {} });
    expect(decode("nope")).toBeNull();
    expect(decode("[1]")).toBeNull();
    expect(decode('{"v":1}')).toBeNull();
    expect(decode("null")).toBeNull();
  });
});

describe("hmac", () => {
  it("matches the protocol test vector", async () => {
    expect(await hmacPin("1234", "00112233445566778899aabbccddeeff", "a1b2c3")).toBe("03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8");
  });
  it("pure-JS fallback (insecure http pages have no crypto.subtle) matches the vector and Node", async () => {
    const enc = new TextEncoder();
    const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
    expect(hex(sha256(enc.encode("abc")))).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(hex(sha256(new Uint8Array(0)))).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    expect(hex(sha256(enc.encode("a".repeat(1000))))).toBe("41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3");
    expect(hex(hmacSha256(enc.encode("1234"), enc.encode("00112233445566778899aabbccddeeffa1b2c3")))).toBe("03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8");
    const { createHmac } = await import("node:crypto");
    const long = "k".repeat(100);
    expect(hex(hmacSha256(enc.encode(long), enc.encode("msg")))).toBe(createHmac("sha256", long).update("msg").digest("hex"));
  });
  it("matches every hmac vector", async () => {
    for (const vec of loadVectors().filter((x) => x.hmac)) expect(await hmacPin(vec.hmac!.pin, vec.hmac!.nonce, vec.hmac!.id)).toBe(vec.msg.mac);
  });
});
