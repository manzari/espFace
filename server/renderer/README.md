# Renderer hosting

Static nginx image serving `web/dist`: the renderer bundle at `/r/1/app.js` + `/r/1/app.css` (immutable cache, CORS `*`) and a landing page at `/` that connects to a device given with `?host=`.

Devices serve a bootstrap page that loads `https://<renderer-host>/r/1/app.js` (`ESPFACE_RENDERER_HOST` in `firmware/src/web/bootstrap.h`, default `https://espface.manzari.dev`). Breaking renderer changes go to `/r/2/`; `/r/1/` stays for old firmware.

## Local

```
docker build -f server/renderer/Dockerfile -t espface-renderer .      # from the repository root
docker run --rm -p 8081:80 espface-renderer
# http://localhost:8081/?host=localhost:8080   (with the fake device running)
```

## Coolify

1. New resource: **Docker Compose** from this git repository.
   - Base directory: `/` (the Dockerfile needs `web/` and `protocol/` in the build context).
   - Docker Compose location: `/server/renderer/docker-compose.yml`.
2. Domain: Coolify fills `SERVICE_FQDN_RENDERER_80` from the domain set on the service (e.g. `https://espface.manzari.dev`). No `ports:` are published; Traefik terminates TLS and proxies to port 80 inside the Coolify network.
3. Deploy. The container is healthy when `GET /healthz` answers `ok`; the compose file uses `expose:` + `healthcheck` and defines neither `container_name` nor top-level `networks:`, as Coolify expects.
4. Redeploys are triggered by the git webhook or manually; the build stage runs `npm ci && npm run build` inside the image, so nothing is built on the host.

Set the device's renderer host at build time with `-DESPFACE_RENDERER_HOST=\"https://your.host\"` or at runtime with `face.setRendererHost(...)` when hosting your own copy.
