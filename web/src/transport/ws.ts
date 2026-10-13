// WebSocket with exponential-backoff reconnect. Text frames go up to onMessage; binary frames carry OTA data.
export interface WsEvents {
  onOpen(): void;
  onClose(): void;
  onMessage(text: string): void;
}

export class WsClient {
  private ws: WebSocket | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private attempt = 0;
  private stopped = false;
  url: string;
  retryAt = 0;

  constructor(host: string, private ev: WsEvents) {
    this.url = `ws://${host}/ws`;
  }

  connect() {
    this.stopped = false;
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    try { this.ws?.close(); } catch { /* ignore */ }
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.onopen = () => { if (ws !== this.ws) return; this.attempt = 0; this.ev.onOpen(); };
    ws.onmessage = (e) => { if (ws === this.ws && typeof e.data === "string") this.ev.onMessage(e.data); };
    ws.onclose = () => { if (ws !== this.ws) return; this.ws = null; this.ev.onClose(); this.schedule(); };
    ws.onerror = () => { /* onclose follows */ };
  }

  private schedule(delay?: number) {
    if (this.stopped || this.timer) return;
    const ms = delay ?? Math.min(10000, 500 * 2 ** Math.min(this.attempt++, 5));
    this.retryAt = Date.now() + ms;
    this.timer = setTimeout(() => { this.timer = null; this.connect(); }, ms);
  }

  reconnect(delay = 0) { this.stopped = false; if (this.ws) this.ws.close(); else { if (this.timer) clearTimeout(this.timer); this.timer = null; this.schedule(delay); } }

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

  close() { this.stopped = true; if (this.timer) clearTimeout(this.timer); this.timer = null; this.ws?.close(); this.ws = null; }
  get open() { return this.ws?.readyState === WebSocket.OPEN; }
  get bufferedAmount() { return this.ws?.bufferedAmount ?? 0; }
}
