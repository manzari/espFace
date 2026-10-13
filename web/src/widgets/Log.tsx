import { useEffect, useRef } from "preact/hooks";
import type { Widget } from "../proto/types";
import { useSub } from "../hooks";
import { store } from "../state";
import { Frame } from "./common";

export const hms = (ms: number) => { const d = new Date(ms); return [d.getHours(), d.getMinutes(), d.getSeconds()].map((n) => String(n).padStart(2, "0")).join(":"); };

export function Log({ w }: { w: Widget }) {
  useSub("l:" + w.id);
  const lines = store.logs.get(w.id) ?? [];
  const box = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  useEffect(() => { const el = box.current; if (el && stick.current) el.scrollTop = el.scrollHeight; });
  return (
    <Frame w={w}>
      <div class="log" ref={box} style={`height:${(w.rows ?? 5) * 1.5 * 0.8 + 1}rem`}
        onScroll={(e) => { const el = e.target as HTMLDivElement; stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 8; }}>
        {lines.map((l, i) => <div key={i} style={l.c ? `color:${l.c}` : ""}><span class="ts">{hms(l.ts)}</span>{l.msg}</div>)}
      </div>
    </Frame>
  );
}
