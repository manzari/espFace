import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { Frame } from "./common";

export function Textblock({ w }: { w: Widget }) {
  return <Frame w={w}><div class="textblock">{w.text ?? ""}</div></Frame>;
}

export function Header({ w }: { w: Widget }) {
  return <Frame w={w} noLabel><h2 class="hdr">{w.icon && <Icon name={w.icon} size={22} />} {w.lbl ?? ""}</h2></Frame>;
}

export function Spacer({ w }: { w: Widget }) {
  const h = Array.isArray(w.size) ? w.size[1] : 16;
  return <div class="w ty-spacer" data-id={w.id} style={`height:${h}px;flex:${Array.isArray(w.size) ? w.size[0] : typeof w.size === "number" ? w.size : 1}`} />;
}

export function Unsupported({ w }: { w: Widget }) {
  return <div class="w" data-id={w.id}><div class="unsupported">unsupported widget "{w.ty}"{w.lbl ? ` (${w.lbl})` : ""}</div></div>;
}
