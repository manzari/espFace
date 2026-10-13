import { useState } from "preact/hooks";
import type { Widget } from "../proto/types";
import { Frame } from "./common";

// MJPEG streams play in a plain <img>; a reload button recovers from a dropped connection.
export function Stream({ w }: { w: Widget }) {
  const [n, setN] = useState(0);
  const [err, setErr] = useState(false);
  if (!w.src) return <Frame w={w}><div class="na">no source</div></Frame>;
  const src = w.src + (n ? (w.src.includes("?") ? "&" : "?") + "r=" + n : "");
  return (
    <Frame w={w}>
      <img class="img" src={src} alt={w.lbl ?? "stream"} onError={() => setErr(true)} onLoad={() => setErr(false)} />
      {err && <button class="btn" onClick={() => { setErr(false); setN(n + 1); }}>Stream unavailable, retry</button>}
    </Frame>
  );
}
