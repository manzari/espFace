export interface Theme { mode: "auto" | "light" | "dark"; accent: string; scale: number; wide: boolean }

const KEY = "espface.theme";
export const defaultTheme: Theme = { mode: "auto", accent: "#2f7df6", scale: 1, wide: false };

export function loadTheme(): Theme {
  try { return { ...defaultTheme, ...JSON.parse(localStorage.getItem(KEY) || "{}") }; } catch { return { ...defaultTheme }; }
}

export function applyTheme(t: Theme) {
  const root = document.documentElement;
  if (t.mode === "auto") root.removeAttribute("data-theme"); else root.setAttribute("data-theme", t.mode);
  root.style.setProperty("--accent", t.accent);
  root.style.setProperty("--fs", String(t.scale));
  root.classList.toggle("wide", t.wide);
}

export function saveTheme(t: Theme) {
  try { localStorage.setItem(KEY, JSON.stringify(t)); } catch { /* ignore */ }
  applyTheme(t);
}
