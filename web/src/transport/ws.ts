// WebSocket with exponential-backoff reconnect. Text frames go up to onMessage; binary frames carry OTA data.
export interface WsEvents {
  onOpen(): void;
  onClose(): void;
  onMessage(text: string): void;
}

export const BACKOFF_BASE_MS = 500;
export const BACKOFF_CAP_MS = 30000;

// 500 ms * 2^attempt, capped at 30 s, with +-25 % jitter so many clients do not retry in lockstep.
export function backoffDelay(attempt: number, rand: () => number = Math.random): number {
  const exp = Math.min(BACKOFF_CAP_MS, BACKOFF_BASE_MS * 2 ** Math.min(attempt, 10));
  return Math.min(BACKOFF_CAP_MS, Math.round(exp * (0.75 + rand() * 0.5)));
}

export class WsClient {
  private ws: WebSocket | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private attempt = 0;
  private stopped = false;
  private paused = false;
  private nextDelay: number | null = null;
  url: string;
  retryAt = 0;
  attempts = 0;

  constructor(host: string, private ev: WsEvents, private opts: { backoff?: (attempt: number) => number } = {}) {
    this.url = `ws://${host}/ws`;
  }

  connect() {
    this.stopped = false;
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    this.detach();
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => { if (ws !== this.ws) return; this.attempt = 0; this.ev.onOpen(); };
    ws.onmessage = (e) => { if (ws === this.ws && typeof e.data === "string") this.ev.onMessage(e.data); };
    ws.onclose = () => { if (ws !== this.ws) return; this.ws = null; this.ev.onClose(); this.schedule(); };
    ws.onerror = () => { /* onclose follows */ };
  }

  // Drops handlers of a stale socket so its late events cannot reach the session or keep it alive.
  private detach() {
    const old = this.ws;
    if (!old) return;
    this.ws = null;
    old.onopen = old.onmessage = old.onclose = old.onerror = null;
    try { old.close(); } catch { /* ignore */ }
  }

  private schedule() {
    if (this.stopped || this.paused || this.timer) return;
    const ms = this.nextDelay ?? (this.opts.backoff ?? backoffDelay)(this.attempt++);
    this.nextDelay = null;
    this.attempts++;
    this.retryAt = Date.now() + ms;
    this.timer = setTimeout(() => { this.timer = null; this.connect(); }, ms);
  }

  // Closes the current socket (if any) and reconnects after `delay` ms (default: now); resets the backoff.
  reconnect(delay = 0) {
    this.stopped = false;
    this.attempt = 0;
    this.nextDelay = delay;
    if (this.ws) { this.ws.close(); return; }
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.schedule();
  }

  // Paused: no automatic reconnects (hidden tab); resume reconnects at once when the socket is gone.
  pause() { this.paused = true; if (this.timer) clearTimeout(this.timer); this.timer = null; }
  resume() { if (!this.paused) return; this.paused = false; if (!this.stopped && !this.ws) this.reconnect(0); }

  send(text: string): boolean {
    if (this.ws?.readyState !== WebSocket.OPEN) return false;
    this.ws.send(text);
    return true;
  }

  sendBinary(buf: ArrayBuffer | Uint8Array): boolean {
    if (this.ws?.readyState !== WebSocket.OPEN) return false;
    this.ws.send(buf);
    return true;
  }

  close() { this.stopped = true; if (this.timer) clearTimeout(this.timer); this.timer = null; this.detach(); }
  get open() { return this.ws?.readyState === WebSocket.OPEN; }
  get bufferedAmount() { return this.ws?.bufferedAmount ?? 0; }
}
