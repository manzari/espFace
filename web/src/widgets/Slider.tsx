import { useRef } from "preact/hooks";
import type { Widget } from "../proto/types";
import { useLocal, useValue } from "../hooks";
import { session } from "../state";
import { Frame, decimals, isRo, num, range } from "./common";

export function Slider({ w }: { w: Widget }) {
  const { min, max, step } = range(w);
  const remote = num(useValue(w.id), min);
  const [v, setV] = useLocal(remote);
  const t = useRef<ReturnType<typeof setTimeout> | null>(null);
  const emit = (x: number, now: boolean) => {
    setV(x);
    if (t.current) clearTimeout(t.current);
    if (now) { t.current = null; session?.set(w.id, x); } else t.current = setTimeout(() => { t.current = null; session?.set(w.id, x); }, 120);
  };
  const text = v.toFixed(decimals(step)) + (w.unit ? " " + w.unit : "");
  return (
    <Frame w={w} val={text}>
      <input type="range" class="slider" min={min} max={max} step={step} value={v} disabled={isRo(w)} style={w.color ? `--sl:${w.color}` : ""}
        onInput={(e) => emit(+(e.target as HTMLInputElement).value, false)} onChange={(e) => emit(+(e.target as HTMLInputElement).value, true)} />
    </Frame>
  );
}
