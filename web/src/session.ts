import { c2d, decode, encode } from "./proto/codec";
import { hmacPin } from "./proto/hmac";
import type { D2C, Value } from "./proto/types";
import type { Store } from "./store";
import { WsClient } from "./transport/ws";

const ls = {
  get(k: string) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k: string, v: string) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  del(k: string) { try { localStorage.removeItem(k); } catch { /* ignore */ } },
};

// Handshake state machine (PROTOCOL.md 3): hello -> auth (PIN) -> time -> traffic, plus reconnect.
export class Session {
  ws: WsClient;
  private lockTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingPin: string | null = null;

  constructor(public store: Store, public host: string) {
    this.ws = new WsClient(host, { onOpen: () => this.onOpen(), onClose: () => this.onClose(), onMessage: (t) => this.onText(t) });
  }

  start() { this.store.setConn("connecting"); this.ws.connect(); }
  stop() { this.ws.close(); }

  private tokenKey(id: string) { return `espface.tok.${id}`; }
  private token(): string | undefined {
    const id = this.store.device?.id ?? ls.get(`espface.id.${this.host}`);
    return (id && ls.get(this.tokenKey(id))) || undefined;
  }

  private onOpen() {
    this.store.setConn("connecting");
    this.send(c2d.hello(this.token()));
  }

  private onClose() {
    if (this.store.conn !== "locked") this.store.setConn("offline");
    this.store.reset();
  }

  private onText(text: string) {
    const m = decode(text);
    if (!m) return;
    this.store.apply(m);
    if (m.t === "hello") this.onHello(m);
    else if (m.t === "auth") this.onAuth(m);
  }

  private onHello(m: Extract<D2C, { t: "hello" }>) {
    ls.set(`espface.id.${this.host}`, m.id);
    if (m.ok) return this.authenticated();
    if (m.lock) return this.locked(m.lock);
    if (this.token()) ls.del(this.tokenKey(m.id));
    if (this.pendingPin && m.nonce) { const pin = this.pendingPin; this.pendingPin = null; void this.submitPin(pin); return; }
    this.store.setConn("pin", this.store.authLeft);
  }

  private onAuth(m: Extract<D2C, { t: "auth" }>) {
    if (m.ok) {
      if (m.tok && this.store.device) ls.set(this.tokenKey(this.store.device.id), m.tok);
      return this.authenticated();
    }
    if (m.lock) return this.locked(m.lock);
    this.store.setConn("pin", m.left);
    this.send(c2d.hello());
  }

  private locked(seconds: number) {
    this.store.lockUntil = Date.now() + seconds * 1000;
    this.store.setConn("locked");
    if (this.lockTimer) clearTimeout(this.lockTimer);
    this.lockTimer = setTimeout(() => { this.lockTimer = null; if (this.ws.open) this.send(c2d.hello(this.token())); else this.ws.reconnect(); }, seconds * 1000 + 500);
  }

  private authenticated() {
    this.store.setConn("ready");
    this.send(c2d.time());
    const first = this.store.firstPage();
    if (this.store.page && this.store.page !== first) this.send(c2d.page(this.store.page));
  }

  async submitPin(pin: string) {
    const d = this.store.device;
    if (!d?.nonce) { this.pendingPin = pin; this.send(c2d.hello()); return; }
    const mac = await hmacPin(pin, d.nonce, d.id);
    d.nonce = undefined;
    this.send(c2d.auth(mac));
  }

  forget() { if (this.store.device) ls.del(this.tokenKey(this.store.device.id)); }

  send(msg: object): boolean { return this.ws.send(encode(msg)); }
  set(id: string, v: Value) { this.store.setLocal(id, v); return this.send(c2d.set(id, v)); }
  ev(id: string, v?: 0 | 1 | "u" | "d" | "l" | "r" | "c") { return this.send(c2d.ev(id, v)); }
  dlg(id: string, ok: boolean, v?: string) { this.store.closeDialog(id); return this.send(c2d.dlg(id, ok, v)); }
  page(id: string) { this.store.setPage(id); return this.send(c2d.page(id)); }
  sys(cmd: string, extra: Record<string, unknown> = {}) { return this.send(c2d.sys(cmd, extra)); }
}

// Dev page (index.html with data-dev) uses ?host= or the remembered host; a device-served page uses its own host.
export function resolveHost(): string | null {
  const q = new URLSearchParams(location.search).get("host");
  if (q) { ls.set("espface.host", q); return q; }
  const dev = document.getElementById("app")?.hasAttribute("data-dev");
  if (!dev) return location.host;
  return ls.get("espface.host");
}

export function rememberHost(h: string) { ls.set("espface.host", h); }
