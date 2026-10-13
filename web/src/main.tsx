import { render } from "preact";
import "uplot/dist/uPlot.min.css";
import "./styles.css";
import { App } from "./app";
import { applyTheme, loadTheme } from "./theme";

// The bootstrap page loads only app.js as a classic script; the stylesheet sits next to it as app.css.
function injectCss() {
  const src = (document.currentScript as HTMLScriptElement | null)?.src;
  if (!src || !/app\.js(\?.*)?$/.test(src)) return;
  const href = src.replace(/app\.js(\?.*)?$/, "app.css");
  if ([...document.styleSheets].some((s) => s.href === href)) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  document.head.appendChild(link);
}

injectCss();
applyTheme(loadTheme());
const root = document.getElementById("app") ?? document.body.appendChild(Object.assign(document.createElement("div"), { id: "app" }));
render(<App />, root);
