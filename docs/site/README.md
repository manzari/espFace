# espFace docs site

VitePress 1.6.4, built in Docker, served under `/docs/` by the renderer image (`server/renderer/Dockerfile`, one Coolify service for renderer + flash page + docs). Nothing is installed on the host.

```
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine npm ci
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine npm run build      # .vitepress/dist
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site -p 5174:5173 node:22-alpine npm run dev   # http://localhost:5174/docs/
```

`npm run build` first runs `scripts/gen-api.mjs` (API reference from `firmware/src/Face.h`, `firmware/src/ui/Ui.h` and the README tables, descriptions and examples from `scripts/api-notes.json`) and `scripts/prepare.mjs` (copies `protocol/PROTOCOL.md`, lists the icons of `web/src/icons.json`). The generated pages (`reference/*.md`, `protocol/index.md`, `guide/icons-list.md`) are git-ignored so they cannot drift from the sources.

Layout: `guide/` (getting started, concepts, widgets, system, transports, security, app, web, fake device, contributing, FAQ), `reference/` (generated API + options), `protocol/` (generated), `.vitepress/config.mts` (nav, sidebar, `base: /docs/`).
