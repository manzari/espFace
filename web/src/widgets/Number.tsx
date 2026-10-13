import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { useLocal, useValue } from "../hooks";
import { session } from "../state";
import { Frame, clamp, decimals, isRo, num, range } from "./common";

export function NumberInput({ w }: { w: Widget }) {
  const { min, max, step } = range(w);
  const remote = num(useValue(w.id), min);
  const [v, setV] = useLocal<string>(String(remote));
  const commit = (x: number) => { const c = +clamp(x, min, max).toFixed(decimals(step)); setV(String(c)); if (c !== remote) session?.set(w.id, c); };
  return (
    <Frame w={w}>
      <div class="inline">
        {w.spin && <button class="btn spin" disabled={isRo(w)} onClick={() => commit(remote - step)}><Icon name="remove" /></button>}
        <input class="field" type="number" inputMode="decimal" min={min} max={max} step={step} value={v} disabled={isRo(w)}
          onInput={(e) => setV((e.target as HTMLInputElement).value)}
          onBlur={() => commit(v === "" ? remote : +v)}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
        {w.spin && <button class="btn spin" disabled={isRo(w)} onClick={() => commit(remote + step)}><Icon name="add" /></button>}
        {w.unit && <span style="color:var(--muted)">{w.unit}</span>}
      </div>
    </Frame>
  );
}
