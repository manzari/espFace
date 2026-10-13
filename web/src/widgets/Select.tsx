import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo, num } from "./common";

export function Select({ w }: { w: Widget }) {
  const opts = Array.isArray(w.opts) ? w.opts : [];
  const v = num(useValue(w.id), 0);
  const pick = (i: number) => { if (i !== v) session?.set(w.id, i); };
  return (
    <Frame w={w}>
      {w.style === "seg" ? (
        <div class="seg">{opts.map((o, i) => <button key={i} class={i === v ? "on" : ""} disabled={isRo(w)} onClick={() => pick(i)}>{o}</button>)}</div>
      ) : (
        <select class="field" value={v} disabled={isRo(w)} onChange={(e) => pick(+(e.target as HTMLSelectElement).value)}>
          {opts.map((o, i) => <option key={i} value={i}>{o}</option>)}
        </select>
      )}
    </Frame>
  );
}
