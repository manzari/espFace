import type { D2C, DlgMsg, ErrMsg, HelloMsg, LogMsg, PropMsg, PtsMsg, SysInfo, SysMsg, UiMsg, UpdMsg, Value, Widget, WifiAp, WifiStatus } from "./proto/types";

export type Listener = () => void;
export interface LogLine { ts: number; msg: string; c?: string }
export interface Dialog { id: string; kind: "confirm" | "prompt"; title?: string; msg: string; def?: string; timeout: number; at: number }
export interface Toast { id: number; lvl: "info" | "warn" | "err"; msg: string; at: number }
export type ConnState = "connecting" | "pin" | "locked" | "ready" | "offline";

export interface RowLayout { kind: "row"; id: string; items: string[] }
export type LayoutItem = string | RowLayout;
export interface Block { kind: "group" | "free"; id: string; items: LayoutItem[] }
export interface PageLayout { id: string; lbl: string; icon?: string; blocks: Block[] }

const UPTIME_LIMIT = 2 ** 40;
const CONSOLE_CAP = 500;
const STRUCTURAL = ["vis", "page", "grp", "row"];

// Everything the renderer shows. Components subscribe to fine-grained keys so only touched widgets re-render.
export class Store {
  rev = -1;
  widgets = new Map<string, Widget>();
  order: string[] = [];
  values = new Map<string, Value>();
  valueAt = new Map<string, number>();
  charts = new Map<string, Map<string, [number, number][]>>();
  logs = new Map<string, LogLine[]>();
  console: LogLine[] = [];
  dialogs: Dialog[] = [];
  toasts: Toast[] = [];
  page = "";
  device: HelloMsg | null = null;
  helloAt = 0;
  conn: ConnState = "connecting";
  authLeft: number | undefined;
  lockUntil = 0;
  sysInfo: SysInfo | null = null;
  wifi: WifiStatus | null = null;
  wifiScan: WifiAp[] | null = null;
  ota: { pct: number; done?: boolean; ok?: boolean; msg?: string } | null = null;
  lastSys: SysMsg | null = null;
  lastErr: ErrMsg | null = null;
  private layoutCache: PageLayout[] | null = null;
  private subs = new Map<string, Set<Listener>>();
  private versions = new Map<string, number>();
  private toastSeq = 0;
  now: () => number = () => Date.now();

  subscribe(key: string, fn: Listener): () => void {
    let s = this.subs.get(key);
    if (!s) this.subs.set(key, (s = new Set()));
    s.add(fn);
    return () => { s!.delete(fn); };
  }

  version(key: string) { return this.versions.get(key) ?? 0; }

  emit(key: string) {
    this.versions.set(key, this.version(key) + 1);
    this.subs.get(key)?.forEach((fn) => fn());
  }

  apply(m: D2C) {
    switch (m.t) {
      case "hello": return this.onHello(m);
      case "ui": return this.onUi(m);
      case "upd": return this.onUpd(m);
      case "pts": return this.onPts(m);
      case "toast": return this.addToast(m.lvl, m.msg);
      case "log": return this.onLog(m);
      case "prop": return this.onProp(m);
      case "dlg": return this.onDlg(m);
      case "sys": return this.onSys(m);
      case "err": return this.onErr(m);
      default: return;
    }
  }

  // ---- session ---------------------------------------------------------
  onHello(m: HelloMsg) {
    this.device = m;
    this.helloAt = this.now();
    if (m.lock) this.lockUntil = this.helloAt + m.lock * 1000;
    this.emit("device");
  }

  setConn(c: ConnState, left?: number) {
    this.conn = c;
    this.authLeft = left;
    this.emit("conn");
  }

  hasCap(cap: string) { return !!this.device?.caps?.includes(cap as never); }

  // Uptime timestamps (< 2^40) are rebased on the hello: wall = helloAt + (ts - up).
  wallMs(ts: number): number {
    if (!Number.isFinite(ts)) return this.now();
    if (ts >= UPTIME_LIMIT) return ts;
    if (!this.device) return this.now();
    return this.helloAt + (ts - this.device.up);
  }

  // ---- ui model --------------------------------------------------------
  onUi(m: UiMsg) {
    if (!Array.isArray(m.w)) return;
    this.rev = typeof m.rev === "number" ? m.rev : this.rev;
    this.widgets.clear();
    this.order = [];
    for (const w of m.w) {
      if (!w || typeof w !== "object" || typeof w.id !== "string" || typeof w.ty !== "string") continue;
      if (this.widgets.has(w.id)) continue;
      this.widgets.set(w.id, { ...w });
      this.order.push(w.id);
    }
    this.layoutCache = null;
    const pages = this.pages();
    if (!pages.some((p) => p.id === this.page)) this.page = pages[0]?.id ?? "";
    this.emit("layout");
    for (const id of this.order) this.emit("w:" + id);
  }

  onProp(m: PropMsg) {
    const w = this.widgets.get(m.id);
    if (!w || !m.p || typeof m.p !== "object") return;
    const p = { ...m.p } as Record<string, unknown>;
    delete p.id; delete p.ty;
    Object.assign(w, p);
    this.emit("w:" + m.id);
    if (STRUCTURAL.some((k) => k in p)) { this.layoutCache = null; this.emit("layout"); }
  }

  firstPage(): string { for (const id of this.order) if (this.widgets.get(id)!.ty === "page") return id; return ""; }

  pageOf(w: Widget): string {
    if (w.page) return w.page;
    const row = w.row ? this.widgets.get(w.row) : undefined;
    if (row?.page) return row.page;
    const grp = (w.grp ? this.widgets.get(w.grp) : undefined) ?? (row?.grp ? this.widgets.get(row.grp) : undefined);
    if (grp?.page) return grp.page;
    return this.firstPage();
  }

  pages(): PageLayout[] { return this.layout(); }

  layout(): PageLayout[] {
    if (this.layoutCache) return this.layoutCache;
    const pages: PageLayout[] = [];
    const byId = new Map<string, PageLayout>();
    const pageFor = (id: string) => {
      let p = byId.get(id);
      if (!p) { const w = this.widgets.get(id); p = { id, lbl: w?.lbl ?? id, icon: w?.icon, blocks: [] }; byId.set(id, p); pages.push(p); }
      return p;
    };
    for (const id of this.order) { const w = this.widgets.get(id)!; if (w.ty === "page") pageFor(id); }
    if (!pages.length) pageFor("");
    const cards = new Map<string, Block>();
    const rows = new Map<string, RowLayout>();
    const free = (p: PageLayout) => {
      const last = p.blocks[p.blocks.length - 1];
      if (last?.kind === "free") return last;
      const b: Block = { kind: "free", id: `free${p.blocks.length}`, items: [] };
      p.blocks.push(b);
      return b;
    };
    for (const id of this.order) {
      const w = this.widgets.get(id)!;
      if (w.ty === "page") continue;
      const p = byId.get(this.pageOf(w)) ?? pages[0];
      if (w.ty === "group") { const b: Block = { kind: "group", id, items: [] }; cards.set(id, b); p.blocks.push(b); continue; }
      const card = w.grp ? cards.get(w.grp) : undefined;
      if (w.ty === "row") { const r: RowLayout = { kind: "row", id, items: [] }; rows.set(id, r); (card ?? free(p)).items.push(r); continue; }
      const row = w.row ? rows.get(w.row) : undefined;
      (row ?? card ?? free(p)).items.push(id);
    }
    return (this.layoutCache = pages);
  }

  setPage(id: string) { if (this.page === id) return; this.page = id; this.emit("page"); }

  // ---- values ----------------------------------------------------------
  onUpd(m: UpdMsg) {
    if (!m.v || typeof m.v !== "object") return;
    const at = this.now();
    for (const [id, v] of Object.entries(m.v)) { this.values.set(id, v); this.valueAt.set(id, at); this.emit("v:" + id); }
  }

  setLocal(id: string, v: Value) { this.values.set(id, v); this.valueAt.set(id, this.now()); this.emit("v:" + id); }

  onPts(m: PtsMsg) {
    if (!Array.isArray(m.p)) return;
    let chart = this.charts.get(m.id);
    if (!chart) this.charts.set(m.id, (chart = new Map()));
    let pts = chart.get(m.s);
    if (!pts) chart.set(m.s, (pts = []));
    for (const p of m.p) {
      if (!Array.isArray(p) || typeof p[0] !== "number" || typeof p[1] !== "number") continue;
      const ts = this.wallMs(p[0]);
      if (pts.length && ts <= pts[pts.length - 1][0]) continue;
      pts.push([ts, p[1]]);
    }
    const win = (this.widgets.get(m.id)?.win ?? 300) * 1000;
    const latest = Math.max(...[...chart.values()].map((s) => s[s.length - 1]?.[0] ?? 0));
    for (const s of chart.values()) { let cut = 0; while (cut < s.length && s[cut][0] < latest - win) cut++; if (cut) s.splice(0, cut); }
    this.emit("c:" + m.id);
  }

  onLog(m: LogMsg) {
    if (typeof m.msg !== "string") return;
    const line: LogLine = { ts: m.ts !== undefined ? this.wallMs(m.ts) : this.now(), msg: m.msg, ...(m.c ? { c: m.c } : {}) };
    if (!m.id) { this.console.push(line); if (this.console.length > CONSOLE_CAP) this.console.splice(0, this.console.length - CONSOLE_CAP); return this.emit("console"); }
    let lines = this.logs.get(m.id);
    if (!lines) this.logs.set(m.id, (lines = []));
    if (m.ts !== undefined && lines.some((l) => l.ts === line.ts && l.msg === line.msg)) return;
    lines.push(line);
    const cap = this.widgets.get(m.id)?.cap ?? 200;
    if (lines.length > cap) lines.splice(0, lines.length - cap);
    this.emit("l:" + m.id);
  }

  // ---- dialogs and toasts ---------------------------------------------
  onDlg(m: DlgMsg) {
    if (m.close) return this.closeDialog(m.id);
    if (m.kind !== "confirm" && m.kind !== "prompt") return;
    if (this.dialogs.some((d) => d.id === m.id)) return;
    this.dialogs.push({ id: m.id, kind: m.kind, title: m.title, msg: m.msg ?? "", def: m.def, timeout: m.timeout ?? 60, at: this.now() });
    this.emit("dlg");
  }

  closeDialog(id: string) {
    const n = this.dialogs.length;
    this.dialogs = this.dialogs.filter((d) => d.id !== id);
    if (this.dialogs.length !== n) this.emit("dlg");
  }

  addToast(lvl: Toast["lvl"], msg: string) {
    this.toasts.push({ id: ++this.toastSeq, lvl: lvl === "warn" || lvl === "err" ? lvl : "info", msg: String(msg), at: this.now() });
    if (this.toasts.length > 5) this.toasts.shift();
    this.emit("toast");
  }

  removeToast(id: number) { this.toasts = this.toasts.filter((t) => t.id !== id); this.emit("toast"); }

  // ---- sys -------------------------------------------------------------
  onErr(m: ErrMsg) {
    this.lastErr = m;
    if (m.ref?.startsWith("ota")) this.ota = { pct: this.ota?.pct ?? 0, done: true, ok: false, msg: m.msg };
    this.addToast("err", `${m.msg ?? "error"}${m.ref ? ` (${m.ref})` : ""} [${m.code}]`);
    this.emit("err");
    if (m.ref?.startsWith("ota")) this.emit("sys:ota");
  }

  onSys(m: SysMsg) {
    this.lastSys = m;
    switch (m.cmd) {
      case "info": this.sysInfo = m as SysInfo; break;
      case "wifi.status": this.wifi = m as WifiStatus; break;
      case "wifi.scan": this.wifiScan = Array.isArray(m.ap) ? (m.ap as WifiAp[]) : []; break;
      case "ota.progress": this.ota = { pct: Math.max(0, Math.min(100, Number(m.pct) || 0)) }; break;
      case "ota.done": this.ota = { pct: m.ok ? 100 : this.ota?.pct ?? 0, done: true, ok: !!m.ok, msg: m.msg }; break;
      case "ota.begin": case "ota.url": this.ota = m.ok === false ? { pct: 0, done: true, ok: false, msg: m.msg } : { pct: 0 }; break;
      case "ota.abort": this.ota = null; break;
      default: break;
    }
    if (["reboot", "pin.set", "revoke", "ota.done"].includes(m.cmd) && typeof m.ok === "boolean") this.addToast(m.ok ? "info" : "err", `${m.cmd}: ${m.ok ? "ok" : m.msg ?? "failed"}`);
    this.emit("sys");
    this.emit("sys:" + m.cmd);
    if (m.cmd.startsWith("ota")) this.emit("sys:ota");
  }

  reset() {
    this.sysInfo = null; this.wifi = null; this.wifiScan = null; this.lastSys = null; this.lastErr = null;
    if (this.ota && !this.ota.done) this.ota = { pct: this.ota.pct, done: true, ok: false, msg: "connection lost" };
    this.emit("sys"); this.emit("sys:ota");
  }
}
