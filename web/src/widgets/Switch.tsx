import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo } from "./common";

export function Switch({ w }: { w: Widget }) {
  const on = useValue(w.id) === true;
  const state = on ? w.on : w.off;
  return (
    <Frame w={w} noLabel>
      <label class={`switch ${on ? "on" : ""}`} style={w.color ? `--sw:${w.color}` : ""}>
        <input type="checkbox" checked={on} disabled={isRo(w)} style="position:absolute;opacity:0;width:0;height:0" onChange={(e) => session?.set(w.id, (e.target as HTMLInputElement).checked)} />
        <span class="track" />
        {w.icon && <Icon name={w.icon} />}
        {w.lbl && <span>{w.lbl}</span>}
        {state && <span class="state">{state}</span>}
      </label>
    </Frame>
  );
}
