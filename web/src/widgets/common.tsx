import type { ComponentChildren } from "preact";
import { useRef } from "preact/hooks";
import type { Value, Widget } from "../proto/types";
import { Icon } from "../icons";
import { store } from "../state";

export const num = (v: Value | undefined, d = 0): number => (typeof v === "number" && Number.isFinite(v) ? v : typeof v === "string" && v !== "" && Number.isFinite(+v) ? +v : d);
export const str = (v: Value | undefined): string => (v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v));
export const hex = (n: number) => "#" + (Math.max(0, Math.min(0xffffff, Math.round(n))) | 0).toString(16).padStart(6, "0");
export const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
export const range = (w: Widget) => ({ min: w.min ?? 0, max: w.max ?? 100, step: w.step ?? 1 });

// printf-style subset: %d %f %.2f %5.1f %s %%
export function fmt(v: Value | undefined, f?: string): string {
  if (!f) return typeof v === "number" ? (Number.isInteger(v) ? String(v) : String(+v.toFixed(2))) : str(v);
  return f.replace(/%(\d*)(?:\.(\d+))?([dfs%])/g, (_, w: string, p: string, c: string) => {
    let s: string;
    if (c === "%") return "%";
    if (c === "s") s = str(v);
    else if (c === "d") s = String(Math.round(num(v)));
    else s = num(v).toFixed(p !== undefined ? +p : 2);
    return w ? s.padStart(+w) : s;
  });
}

export function decimals(step: number) { const s = String(step); const i = s.indexOf("."); return i < 0 ? 0 : s.length - i - 1; }

// Long-press (touch) or right-click shows the hint as a toast; hover uses the title attribute.
function hintHandlers(w: Widget) {
  if (!w.hint) return {};
  let t: ReturnType<typeof setTimeout> | null = null;
  const show = () => store.addToast("info", w.hint!);
  return {
    title: w.hint,
    onPointerDown: () => { t = setTimeout(() => { t = null; show(); }, 600); },
    onPointerUp: () => { if (t) clearTimeout(t); t = null; },
    onPointerLeave: () => { if (t) clearTimeout(t); t = null; },
    onContextMenu: (e: Event) => { e.preventDefault(); show(); },
  };
}

export function Frame({ w, val, children, noLabel, class: cls }: { w: Widget; val?: string; children: ComponentChildren; noLabel?: boolean; class?: string }) {
  const h = useRef<Record<string, unknown>>();
  if (!h.current || h.current.title !== w.hint) h.current = hintHandlers(w);
  const style: Record<string, string> = {};
  if (Array.isArray(w.size) && w.size[1]) style.height = w.size[1] + "px";
  const classes = ["w", "ty-" + w.ty, w.dis ? "dis" : "", w.sq ? "sq" : "", cls ?? ""].join(" ");
  return (
    <div class={classes} data-id={w.id} style={style} {...h.current}>
      {!noLabel && (w.lbl || w.icon || val !== undefined) && (
        <div class="lbl">{w.icon && <Icon name={w.icon} size={16} />}{w.lbl && <span>{w.lbl}</span>}{val !== undefined && <span class="val">{val}</span>}</div>
      )}
      {children}
    </div>
  );
}

export const isRo = (w: Widget) => !!(w.ro || w.dis);
