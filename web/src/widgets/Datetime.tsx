import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo, num } from "./common";

const pad = (n: number) => String(n).padStart(2, "0");

// Values are unix seconds in local time; mode "time" counts seconds since local midnight.
function toInput(mode: string, unix: number): string {
  if (mode === "time") return `${pad(Math.floor(unix / 3600) % 24)}:${pad(Math.floor(unix / 60) % 60)}`;
  const d = new Date(unix * 1000);
  const date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return mode === "date" ? date : `${date}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromInput(mode: string, s: string): number | null {
  if (!s) return null;
  if (mode === "time") { const [h, m] = s.split(":").map(Number); return h * 3600 + m * 60; }
  const t = new Date(mode === "date" ? s + "T00:00" : s).getTime();
  return Number.isFinite(t) ? Math.floor(t / 1000) : null;
}

export function Datetime({ w }: { w: Widget }) {
  const mode = w.mode ?? "datetime";
  const v = num(useValue(w.id), 0);
  const type = mode === "date" ? "date" : mode === "time" ? "time" : "datetime-local";
  return (
    <Frame w={w}>
      <input class="field" type={type} value={toInput(mode, v)} disabled={isRo(w)}
        onChange={(e) => { const x = fromInput(mode, (e.target as HTMLInputElement).value); if (x !== null) session?.set(w.id, x); }} />
    </Frame>
  );
}
