import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { useValue } from "../hooks";
import { Frame, hex, num } from "./common";

export function Led({ w }: { w: Widget }) {
  const v = useValue(w.id);
  const on = w.rgb ? num(v, 0) > 0 : v === true || (typeof v === "number" && v !== 0);
  const color = w.rgb ? hex(num(v, 0)) : (w.color ?? "var(--accent)");
  return (
    <Frame w={w} noLabel>
      <div class="led" style={`--led:${color}`}>
        <span class={`lamp ${on ? "" : "off"}`} />
        {w.icon && <Icon name={w.icon} />}
        {w.lbl && <span>{w.lbl}</span>}
      </div>
    </Frame>
  );
}
