import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { Frame, str } from "./common";

// Seven-segment style readout: fixed digit count, ghost "8"s behind the value.
export function Display({ w }: { w: Widget }) {
  const v = useValue(w.id);
  const digits = w.digits ?? 4;
  let s = str(v);
  if (typeof v === "number") { s = Number.isInteger(v) ? String(v) : v.toFixed(Math.max(0, digits - String(Math.trunc(v)).length - 1)); }
  const width = digits + (s.includes(".") ? 1 : 0);
  const text = s.length > width ? s.slice(0, width) : s.padStart(width);
  return (
    <Frame w={w}>
      <div class="display">
        <span class="ghost">{"8".repeat(digits)}</span>
        <span class="num">{text}</span>
        {w.unit && <span class="u">{w.unit}</span>}
      </div>
    </Frame>
  );
}
