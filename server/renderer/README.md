# Renderer hosting

Static nginx image serving `web/dist` plus the docs site: the renderer bundle at `/r/1/app.js` + `/r/1/app.css` (immutable cache, CORS `*`), a landing page at `/` (links to docs, flash page and a connect form), `/connect/?host=` to open a device, `/flash/`, a WebSerial flash page (esptool-js from jsdelivr, Chromium only; Web Serial needs the https origin Traefik provides), and `/docs/`, the VitePress site from `docs/site/` (built in its own stage of the Dockerfile, so the API reference is regenerated from the firmware headers on every deploy).

Devices serve the renderer from their own flash since firmware 1.0.x; devices flashed with 1.0.0 load `https://espface.manzari.dev/r/1/app.js`, the host this image had until 2026-11-20. That host is the landing page now and redirects `/r/`, `/connect/`, `/flash/` and `/docs/` here (`promo/renderer-host.conf`). Breaking renderer changes go to `/r/2/`; `/r/1/` stays for old firmware.

## Local

```
docker build -f server/renderer/Dockerfile -t espface-renderer .      # from the repository root
docker run --rm -p 8081:80 espface-renderer
# http://localhost:8081/connect/?host=localhost:18080   (with the fake device running), http://localhost:8081/docs/
```

## Coolify

1. New resource: **Docker Compose** from this git repository.
   - Base directory: `/` (the Dockerfile needs `web/` and `protocol/` in the build context).
   - Docker Compose location: `/server/renderer/docker-compose.yml`.
2. Domain: Coolify fills `SERVICE_FQDN_RENDERER_80` from the domain set on the service (`https://r.espface.manzari.dev`). No `ports:` are published; Traefik terminates TLS and proxies to port 80 inside the Coolify network.
3. Deploy. The container is healthy when `GET /healthz` answers `ok`; the compose file uses `expose:` + `healthcheck` and defines neither `container_name` nor top-level `networks:`, as Coolify expects.
4. Redeploys are triggered by the git webhook or manually; the build stage runs `npm ci && npm run build` inside the image, so nothing is built on the host.
