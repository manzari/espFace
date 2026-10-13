import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame, fmt } from "./common";

export function Label({ w }: { w: Widget }) {
  const v = useValue(w.id);
  return (
    <Frame w={w}>
      <div style="font-size:1.15rem;font-variant-numeric:tabular-nums">{fmt(v, w.fmt)}{w.unit && typeof v === "number" ? <span style="color:var(--muted);font-size:.85rem"> {w.unit}</span> : null}</div>
    </Frame>
  );
}
