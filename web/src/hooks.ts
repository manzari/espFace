import { useEffect, useLayoutEffect, useReducer, useRef, useState } from "preact/hooks";
import type { Store } from "./store";
import type { Value, Widget } from "./proto/types";
import { store } from "./state";

// Re-renders the component when any of the keys is emitted by the store. Subscribes synchronously after
// commit and catches emits that landed between render and subscription (fast device replies).
export function useSub(keys: string | string[], s: Store = store) {
  const [, bump] = useReducer((n: number) => n + 1, 0) as [number, () => void];
  const list = Array.isArray(keys) ? keys : [keys];
  const seen = list.map((k) => s.version(k));
  useLayoutEffect(() => {
    const offs = list.map((k) => s.subscribe(k, bump));
    if (list.some((k, i) => s.version(k) !== seen[i])) bump();
    return () => offs.forEach((off) => off());
  }, [list.join("|")]);
}

export function useWidget(id: string): Widget {
  useSub("w:" + id);
  return store.widgets.get(id) ?? { id, ty: "?" };
}

export function useValue(id: string): Value | undefined {
  useSub("v:" + id);
  return store.values.get(id);
}

// Local editable copy of a value that follows the store until the user edits it.
export function useLocal<T>(remote: T): [T, (v: T) => void] {
  const [local, setLocal] = useState<T>(remote);
  const last = useRef(remote);
  if (last.current !== remote) { last.current = remote; if (local !== remote) setLocal(remote); }
  return [local, setLocal];
}

export function useTick(ms: number) {
  const [, bump] = useReducer((n: number) => n + 1, 0) as [number, () => void];
  useEffect(() => { const t = setInterval(bump, ms); return () => clearInterval(t); }, [ms]);
}
