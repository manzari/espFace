import { useMemo, useRef } from "preact/hooks";
import type { Widget } from "../proto/types";
import { useLocal, useValue } from "../hooks";
import { session } from "../state";
import { Frame, clamp, isRo } from "./common";

// Pointer events cover touch and mouse. x right, y up, -100..100; exp applies a squared curve for fine control.
export function Joystick({ w }: { w: Widget }) {
  const raw = useValue(w.id);
  const remote = useMemo<[number, number]>(() => (Array.isArray(raw) && raw.length === 2 ? [Number(raw[0]) || 0, Number(raw[1]) || 0] : [0, 0]), [raw]);
  const [pos, setPos] = useLocal<[number, number]>(remote);
  const pad = useRef<HTMLDivElement>(null);
  const last = useRef(0);
  const active = useRef(false);
  const curve = (v: number) => (w.exp ? Math.sign(v) * (v * v) / 100 : v);
  const send = (p: [number, number], force: boolean) => {
    const now = Date.now();
    if (!force && now - last.current < 50) return;
    last.current = now;
    session?.set(w.id, [Math.round(curve(p[0])), Math.round(curve(p[1]))]);
  };
  const update = (e: PointerEvent, force = false) => {
    const r = pad.current!.getBoundingClientRect();
    const x = clamp(((e.clientX - r.left) / r.width) * 200 - 100, -100, 100);
    const y = clamp(100 - ((e.clientY - r.top) / r.height) * 200, -100, 100);
    const p: [number, number] = [Math.round(x), Math.round(y)];
    setPos(p);
    send(p, force);
  };
  const down = (e: PointerEvent) => { if (isRo(w)) return; active.current = true; pad.current!.setPointerCapture(e.pointerId); update(e, true); };
  const move = (e: PointerEvent) => { if (active.current) update(e); };
  const up = (e: PointerEvent) => {
    if (!active.current) return;
    active.current = false;
    if (w.center !== false) { setPos([0, 0]); session?.set(w.id, [0, 0]); } else update(e, true);
  };
  const kx = 50 + pos[0] / 2, ky = 50 - pos[1] / 2;
  return (
    <Frame w={w} val={`${pos[0]}, ${pos[1]}`}>
      <div class="joy" ref={pad} onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
        <div class="cross" /><div class="cross v" />
        <div class="knob" style={`left:${kx}%;top:${ky}%`} />
      </div>
    </Frame>
  );
}
