import { useMemo, useState } from "preact/hooks";
import type { Widget } from "../proto/types";
import { Icon } from "../icons";
import { useLocal, useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo, str } from "./common";

export function Text({ w }: { w: Widget }) {
  const remote = str(useValue(w.id));
  const [v, setV] = useLocal(remote);
  const [show, setShow] = useState(false);
  const re = useMemo(() => { try { return w.re ? new RegExp(w.re) : null; } catch { return null; } }, [w.re]);
  const ok = !re || re.test(v);
  const commit = () => { if (ok && v !== remote) session?.set(w.id, v); };
  return (
    <Frame w={w}>
      <div class="inline">
        <input class={`field ${ok ? "" : "bad"}`} type={w.secret && !show ? "password" : "text"} maxLength={w.maxlen} value={v} disabled={isRo(w)} autoComplete="off"
          onInput={(e) => setV((e.target as HTMLInputElement).value)} onBlur={commit}
          onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }} />
        {w.secret && <button class="btn spin" type="button" onClick={() => setShow(!show)}><Icon name={show ? "visibility_off" : "visibility"} /></button>}
      </div>
      {!ok && <div style="color:var(--danger);font-size:.8rem">Does not match {w.re}</div>}
    </Frame>
  );
}
