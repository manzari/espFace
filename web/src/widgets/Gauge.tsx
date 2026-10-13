import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame, clamp, fmt, num, range } from "./common";

const polar = (cx: number, cy: number, r: number, deg: number) => [cx + r * Math.cos((deg * Math.PI) / 180), cy + r * Math.sin((deg * Math.PI) / 180)];

function arcPath(cx: number, cy: number, r: number, a0: number, a1: number) {
  if (a1 - a0 >= 359.9) a1 = a0 + 359.9;
  const [x0, y0] = polar(cx, cy, r, a0), [x1, y1] = polar(cx, cy, r, a1);
  return `M${x0.toFixed(2)} ${y0.toFixed(2)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

export function Gauge({ w }: { w: Widget }) {
  const { min, max } = range(w);
  const raw = useValue(w.id);
  const v = num(raw, min);
  const frac = max > min ? clamp((v - min) / (max - min), 0, 1) : 0;
  const zones = Array.isArray(w.zones) ? w.zones : [];
  const zoneColor = zones.find((z) => v >= z.from && v <= z.to)?.color;
  const color = zoneColor ?? w.color ?? "var(--accent)";
  const text = fmt(raw, w.fmt);
  const style = w.style ?? "arc";

  if (style === "linear") {
    const pct = (x: number) => clamp(((x - min) / (max - min)) * 100, 0, 100);
    return (
      <Frame w={w} val={text + (w.unit ? " " + w.unit : "")} class="gauge linear">
        <div class="bar">
          {zones.map((z, i) => <div key={i} class="zone" style={`left:${pct(z.from)}%;width:${pct(z.to) - pct(z.from)}%;background:${z.color}`} />)}
          <div class="fill" style={`width:${frac * 100}%;background:${color}`} />
          <div class="mark" style={`left:calc(${frac * 100}% - 1px)`} />
        </div>
      </Frame>
    );
  }
  const round = style === "round";
  const start = round ? -90 : 135, sweep = round ? 360 : 270;
  const r = 40, sw = 9, cx = 50, cy = round ? 50 : 52;
  const h = round ? 100 : 86;
  const ang = (x: number) => start + (clamp((x - min) / (max - min), 0, 1)) * sweep;
  return (
    <Frame w={w} class="gauge">
      <svg viewBox={`0 0 100 ${h}`} style="max-width:220px;margin:0 auto">
        <path d={arcPath(cx, cy, r, start, start + sweep)} fill="none" stroke="var(--input)" stroke-width={sw} stroke-linecap="round" />
        {zones.map((z, i) => <path key={i} d={arcPath(cx, cy, r, ang(z.from), ang(z.to))} fill="none" stroke={z.color} stroke-width={sw} opacity=".35" />)}
        {frac > 0 && <path d={arcPath(cx, cy, r, start, start + frac * sweep)} fill="none" stroke={color} stroke-width={sw} stroke-linecap="round" />}
        <text class="num" x={cx} y={cy + 6}>{text}</text>
        {w.unit && <text class="unit" x={cx} y={cy + 17}>{w.unit}</text>}
      </svg>
    </Frame>
  );
}
