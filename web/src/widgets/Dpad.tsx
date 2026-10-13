import { useRef } from "preact/hooks";
import type { Widget } from "../proto/types";
import { session } from "../state";
import { Frame, isRo } from "./common";

type Dir = "u" | "d" | "l" | "r" | "c";
const KEYS: [Dir, string, string][] = [["u", "1 / 2", "▲"], ["l", "2 / 1", "◀"], ["c", "2 / 2", "●"], ["r", "2 / 3", "▶"], ["d", "3 / 2", "▼"]];

export function Dpad({ w }: { w: Widget }) {
  const held = useRef<Dir | null>(null);
  const press = (d: Dir) => (e: Event) => { e.preventDefault(); if (held.current || isRo(w)) return; held.current = d; session?.ev(w.id, d); };
  const release = () => { if (!held.current) return; held.current = null; session?.ev(w.id, 0); };
  return (
    <Frame w={w}>
      <div class="dpad">
        {KEYS.map(([d, area, glyph]) => (
          <button key={d} class="btn" style={`grid-area:${area}`} disabled={isRo(w)} data-dir={d}
            onPointerDown={press(d)} onPointerUp={release} onPointerCancel={release} onPointerLeave={release}>{glyph}</button>
        ))}
      </div>
    </Frame>
  );
}
