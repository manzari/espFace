// Shared icon subset (src/icons.json, Material Icons filled) as inline SVG; unknown names get the fallback glyph.
import { FALLBACK, P } from "./icons-paths";

export const iconNames = Object.keys(P);
export const hasIcon = (name?: string) => !!name && name in P;

export function Icon({ name, size = 20, class: cls }: { name?: string; size?: number; class?: string }) {
  const d = P[name ?? ""] ?? FALLBACK;
  return <svg class={`ic ${cls ?? ""}`} width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d={d} /></svg>;
}
