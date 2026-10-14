import { defineConfig } from "vitepress";

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
        ],
      },
    ],
    socialLinks: [{ icon: "github", link: "https://github.com/manzari/espFace" }],
    outline: { level: [2, 3] },
    search: { provider: "local" },
    footer: { message: "MIT licensed. Firmware, web renderer and apps.", copyright: "espFace" },
  },
  markdown: { lineNumbers: false },
});
