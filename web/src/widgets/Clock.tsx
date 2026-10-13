import type { Widget } from "../proto/types";
import { useTick, useValue } from "../hooks";
import { store } from "../state";
import { Frame, num } from "./common";

const pad = (n: number, l = 2) => String(n).padStart(l, "0");

// fmt tokens: YYYY MM DD HH mm ss; default "HH:mm:ss".
export function formatClock(d: Date, f = "HH:mm:ss") {
  return f.replace(/YYYY|MM|DD|HH|mm|ss/g, (t) => ({ YYYY: String(d.getFullYear()), MM: pad(d.getMonth() + 1), DD: pad(d.getDate()), HH: pad(d.getHours()), mm: pad(d.getMinutes()), ss: pad(d.getSeconds()) })[t]!);
}

// The device pushes unix seconds once in a while; the client ticks locally from the moment it arrived.
export function Clock({ w }: { w: Widget }) {
  const v = useValue(w.id);
  useTick(1000);
  const at = store.valueAt.get(w.id) ?? Date.now();
  const unix = num(v, 0);
  const text = unix ? formatClock(new Date(unix * 1000 + (Date.now() - at)), w.fmt) : "--:--:--";
  return <Frame w={w}><div class="clock">{text}</div></Frame>;
}
