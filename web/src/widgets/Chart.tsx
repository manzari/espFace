import { useEffect, useRef, useState } from "preact/hooks";
import uPlot from "uplot";
import type { Widget } from "../proto/types";
import { useSub } from "../hooks";
import { store } from "../state";
import { Frame, decimals } from "./common";
import { hms } from "./Log";

const PALETTE = ["#2f7df6", "#ff8800", "#1f9d55", "#d9342b", "#8e44ad", "#16a085", "#c77700", "#7f8c8d"];

// Merges per-series ring buffers into uPlot's aligned [xs, y1, y2, ...] layout (seconds on x).
function align(series: { id: string }[], bufs: Map<string, [number, number][]> | undefined): uPlot.AlignedData {
  const ts = new Set<number>();
  for (const s of series) for (const p of bufs?.get(s.id) ?? []) ts.add(p[0]);
  const xs = [...ts].sort((a, b) => a - b);
  const idx = new Map(xs.map((t, i) => [t, i]));
  const ys = series.map((s) => {
    const col: (number | null)[] = new Array(xs.length).fill(null);
    for (const p of bufs?.get(s.id) ?? []) col[idx.get(p[0])!] = p[1];
    return col;
  });
  return [xs.map((t) => t / 1000), ...ys] as uPlot.AlignedData;
}

export function Chart({ w }: { w: Widget }) {
  useSub("c:" + w.id);
  const series = Array.isArray(w.series) ? w.series : [];
  const host = useRef<HTMLDivElement>(null);
  const plot = useRef<uPlot | null>(null);
  const [showLegend, setShowLegend] = useState(w.legend !== false);
  const bufs = store.charts.get(w.id);
  const style = w.style ?? "line";
  const data = align(series, bufs);
  const empty = data[0].length === 0;

  useEffect(() => {
    if (!host.current || empty) return;
    const el = host.current;
    const width = el.clientWidth || 300;
    if (!plot.current) {
      const css = getComputedStyle(el);   // canvas strokes cannot use var(--x)
      const muted = css.getPropertyValue("--muted").trim() || "#888", border = css.getPropertyValue("--border").trim() || "#ccc";
      const opts: uPlot.Options = {
        width, height: 180,
        legend: { show: false },
        cursor: { show: false },
        scales: { x: { time: true } },
        axes: [
          { stroke: muted, grid: { stroke: border, width: 1 }, ticks: { stroke: border }, font: "11px system-ui", space: 60,
            values: (_u, v, _a, _s, incr) => v.map((x) => (incr >= 60 ? hms(x * 1000).slice(0, 5) : hms(x * 1000))) },
          { stroke: muted, grid: { stroke: border, width: 1 }, ticks: { stroke: border }, font: "11px system-ui", size: 44, values: (_u, v) => v.map((x) => String(x) + (w.unit ?? "")) },
        ],
        series: [
          {},
          ...series.map((s, i) => {
            const color = s.color ?? PALETTE[i % PALETTE.length];
            const base: uPlot.Series = { label: s.lbl ?? s.id, stroke: color, width: 2, spanGaps: true, points: { show: false } };
            if (style === "bar") { base.paths = uPlot.paths.bars!({ size: [0.6, 20] }); base.fill = color; }
            if (style === "area") base.fill = color + "33";
            return base;
          }),
        ],
      };
      plot.current = new uPlot(opts, data, el);
    } else plot.current.setData(data);
  });

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    const ro = new ResizeObserver(() => { if (plot.current && el.clientWidth) plot.current.setSize({ width: el.clientWidth, height: 180 }); });
    ro.observe(el);
    return () => { ro.disconnect(); plot.current?.destroy(); plot.current = null; };
  }, [style, series.map((s) => s.id).join(",")]);

  return (
    <Frame w={w} class="chart">
      {showLegend && (
        <div class="legend">
          {series.map((s, i) => {
            const pts = bufs?.get(s.id);
            const last = pts?.[pts.length - 1]?.[1];
            return <span key={s.id}><span class="sw" style={`background:${s.color ?? PALETTE[i % PALETTE.length]}`} />{s.lbl ?? s.id}{w.vals && last !== undefined ? <> <b>{last.toFixed(decimals(0.1))}{w.unit ?? ""}</b></> : null}</span>;
          })}
          <button class="iconbtn" style="padding:0 4px;font-size:.75rem;margin-left:auto" onClick={() => setShowLegend(false)}>hide</button>
        </div>
      )}
      {!showLegend && w.legend !== false && <button class="iconbtn" style="padding:0 4px;font-size:.75rem;align-self:flex-end" onClick={() => setShowLegend(true)}>legend</button>}
      {empty ? <div class="empty">waiting for data</div> : <div ref={host} />}
    </Frame>
  );
}
