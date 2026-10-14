import { readFileSync } from "node:fs";
import { defineConfig } from "vitepress";

const VERSION = (JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")) as { version: string }).version;
const REPO = "https://git.hauptstadt.monster/manzari/espFace";
const GIT_ICON = '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="currentColor" d="M6 3a3 3 0 0 0-1 5.83v6.34A3 3 0 1 0 7 15.17V13a3 3 0 0 1 3-3h4a5 5 0 0 0 5-5V8.83a3 3 0 1 0-2 0V5a3 3 0 0 1-3 3h-4a4.98 4.98 0 0 0-3 1V8.83A3 3 0 0 0 6 3z"/></svg>';

// Served from the renderer host under /docs/ (server/renderer/nginx.conf).
export default defineConfig({
  title: "espFace",
  description: "An ESP32 describes its control UI in a few lines of Arduino code; native apps and a web renderer draw it.",
  base: "/docs/",
  lang: "en",
  lastUpdated: false,
  cleanUrls: false,
  ignoreDeadLinks: [/^https?:\/\/localhost/, /^\/flash/, /^\/connect/],
  head: [["link", { rel: "icon", href: "/docs/favicon.svg" }]],
  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide/getting-started" },
      { text: "Widgets", link: "/guide/widgets" },
      { text: "API", link: "/reference/espface" },
      { text: "Protocol", link: "/protocol/" },
      { text: "Flash", link: "/flash/", target: "_self" },
      { text: `v${VERSION}`, link: `${REPO}/src/branch/main/CHANGELOG.md` },
    ],
    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "Getting started", link: "/guide/getting-started" },
          { text: "Concepts", link: "/guide/concepts" },
          { text: "Widget catalogue", link: "/guide/widgets" },
          { text: "Icons", link: "/guide/icons" },
          { text: "System features", link: "/guide/system" },
          { text: "Transports", link: "/guide/transports" },
          { text: "Security model", link: "/guide/security" },
        ],
      },
      {
        text: "Clients",
        items: [
          { text: "Mobile app", link: "/guide/app" },
          { text: "Web renderer", link: "/guide/web" },
          { text: "Fake device", link: "/guide/fake-device" },
        ],
      },
      {
        text: "Reference",
        items: [
          { text: "EspFace", link: "/reference/espface" },
          { text: "Ui builder", link: "/reference/ui" },
          { text: "WidgetRef", link: "/reference/widgetref" },
          { text: "PropRef", link: "/reference/propref" },
          { text: "Compile-time options", link: "/reference/options" },
          { text: "Protocol v1", link: "/protocol/" },
        ],
      },
      {
        text: "Project",
        items: [
          { text: "Contributing and CI", link: "/guide/contributing" },
          { text: "FAQ and troubleshooting", link: "/guide/faq" },
          { text: "Privacy policy", link: "/guide/privacy" },
        ],
      },
    ],
    socialLinks: [{ icon: { svg: GIT_ICON }, link: REPO, ariaLabel: "Source repository" }],
    outline: { level: [2, 3] },
    search: { provider: "local" },
    footer: { message: "MIT licensed. Firmware, web renderer and apps.", copyright: "espFace" },
  },
  markdown: { lineNumbers: false },
});
