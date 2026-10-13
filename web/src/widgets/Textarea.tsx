import type { Widget } from "../proto/types";
import { useLocal, useValue } from "../hooks";
import { session } from "../state";
import { Frame, isRo, str } from "./common";

export function Textarea({ w }: { w: Widget }) {
  const remote = str(useValue(w.id));
  const [v, setV] = useLocal(remote);
  return (
    <Frame w={w}>
      <textarea class="field" rows={w.rows ?? 5} maxLength={w.maxlen} value={v} disabled={isRo(w)}
        onInput={(e) => setV((e.target as HTMLTextAreaElement).value)} onBlur={() => { if (v !== remote) session?.set(w.id, v); }} />
    </Frame>
  );
}
