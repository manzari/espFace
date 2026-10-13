import type { Widget } from "../proto/types";
import { useValue } from "../hooks";
import { session } from "../state";
import { Frame, hex, isRo, num } from "./common";

export function Color({ w }: { w: Widget }) {
  const v = hex(num(useValue(w.id), 0));
  return (
    <Frame w={w} val={v}>
      <input type="color" class="color" value={v} disabled={isRo(w)} onChange={(e) => session?.set(w.id, parseInt((e.target as HTMLInputElement).value.slice(1), 16))} />
    </Frame>
  );
}
