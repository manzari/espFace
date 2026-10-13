import { useRef, useState } from "preact/hooks";
import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { session } from "../state";
import { Frame, isRo } from "./common";

export function Button({ w }: { w: Widget }) {
  const [down, setDown] = useState(false);
  const held = useRef(false);
  const style = w.color ? `background:${w.color};border-color:${w.color};color:#fff` : "";
  const press = (e: Event) => {
    if (!w.hold || held.current) return;
    e.preventDefault();
    held.current = true; setDown(true);
    session?.ev(w.id, 1);
  };
  const release = () => {
    if (!w.hold || !held.current) return;
    held.current = false; setDown(false);
    session?.ev(w.id, 0);
  };
  return (
    <Frame w={w} noLabel>
      <button class={`btn ${down ? "pressed" : ""}`} style={style} disabled={isRo(w)}
        onClick={() => { if (!w.hold) session?.ev(w.id); }}
        onPointerDown={press} onPointerUp={release} onPointerCancel={release} onPointerLeave={release}>
        {w.icon && <Icon name={w.icon} />}{w.lbl ?? w.id}
      </button>
    </Frame>
  );
}
