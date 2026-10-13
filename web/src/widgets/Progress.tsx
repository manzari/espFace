import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame, clamp, fmt, num, range } from "./common";

export function Progress({ w }: { w: Widget }) {
  const { min, max } = range(w);
  const raw = useValue(w.id);
  const v = num(raw, min);
  const pct = (x: number) => clamp(((x - min) / (max - min)) * 100, 0, 100);
  let left: number, width: number;
  if (w.center) {
    const mid = pct((min + max) / 2), p = pct(v);
    left = Math.min(mid, p); width = Math.abs(p - mid);
  } else { left = 0; width = pct(v); }
  return (
    <Frame w={w} val={fmt(raw, w.fmt) + (w.unit ? " " + w.unit : "")}>
      <div class="bar" style={w.color ? `--pc:${w.color}` : ""}>
        <div class="fill" style={`left:${left}%;width:${width}%`} />
        {w.center && <div class="mid" />}
      </div>
    </Frame>
  );
}
