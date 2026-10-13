import type { Widget } from "../proto/types";
import { Frame } from "./common";

export function Image({ w }: { w: Widget }) {
  return <Frame w={w}>{w.src ? <img class="img" src={w.src} alt={w.lbl ?? ""} /> : <div class="na">no source</div>}</Frame>;
}
