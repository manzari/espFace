import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame, str } from "./common";

export function Table({ w }: { w: Widget }) {
  const v = useValue(w.id);
  const cols = Array.isArray(w.cols) ? w.cols : [];
  const rows = Array.isArray(v) ? (v as unknown[]).filter(Array.isArray) as (string | number)[][] : [];
  const total = cols.reduce((a, c) => a + (c.w ?? 1), 0) || 1;
  return (
    <Frame w={w}>
      <table class="tbl">
        {cols.length > 0 && <thead><tr>{cols.map((c, i) => <th key={i} style={`width:${((c.w ?? 1) / total) * 100}%;text-align:${c.align ?? "left"}`}>{c.lbl ?? ""}</th>)}</tr></thead>}
        <tbody>{rows.map((r, i) => <tr key={i}>{r.map((cell, j) => <td key={j} style={`text-align:${cols[j]?.align ?? "left"}`}>{str(cell)}</td>)}</tr>)}</tbody>
      </table>
    </Frame>
  );
}
