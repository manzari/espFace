import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo, num } from "./common";

export function Flags({ w }: { w: Widget }) {
  const opts = Array.isArray(w.opts) ? w.opts.slice(0, 32) : [];
  const v = num(useValue(w.id), 0) >>> 0;
  return (
    <Frame w={w}>
      <div class="chips">
        {opts.map((o, i) => {
          const on = (v & (1 << i)) !== 0;
          return <button key={i} class={on ? "on" : ""} disabled={isRo(w)} onClick={() => session?.set(w.id, (v ^ (1 << i)) >>> 0)}>{o}</button>;
        })}
      </div>
    </Frame>
  );
}
