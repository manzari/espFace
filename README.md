# espFace

An ESP32 describes its control UI in a few lines of Arduino code; native Android/iOS apps and a web renderer draw it. Plan: `docs/PLAN.md`. Protocol: `protocol/PROTOCOL.md`. Documentation site: `docs/site/` (built in Docker, served at `https://<renderer-host>/docs/`, API reference generated from the firmware headers).

```
protocol/           JSON schema v1, test vectors, validator      (phase 0, done)
tools/fake-device/  Node reference implementation of a device    (phase 0, done; hardening knobs phase 6)
firmware/           Arduino library                              (phases 1, 1b, 4, 5, done)
web/                TypeScript renderer                          (phases 2, 4, 6, done)
apps/mobile/        Flutter app                                  (phases 3, 5, 6, done)
server/renderer/    nginx image: renderer + flash page + docs    (Coolify)
docs/site/          VitePress docs site                          (phase 6, done)
promo/              landing page for the app                     (Coolify)
docker/             build and run images
```

Everything runs in Docker so the host needs nothing but Docker:

```
# validate protocol vectors
docker run --rm -v "$PWD/protocol":/w -w /w node:22-alpine sh -c "npm install && npm test"
# fake device on ws://localhost:18080/ws (host port 8080 is often taken); hardening knobs see tools/fake-device/README.md
docker build -f docker/fake-device.Dockerfile -t espface-fake . && docker run --rm -p 18080:8080 espface-fake --pin=1234
# docs site
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine sh -c "npm ci && npm run build"
# renderer + flash + docs image (what Coolify deploys)
docker build -f server/renderer/Dockerfile -t espface-renderer . && docker run --rm -p 8081:80 espface-renderer   # http://localhost:8081/docs/
# landing page preview on http://localhost:8888 (placeholder privacy policy and terms)
docker build --build-arg ALLOW_PLACEHOLDER_LEGAL=1 -t espface-promo promo && docker run --rm -p 8888:80 espface-promo
```

## Landing page

`promo/` is the landing page at `https://espface.manzari.dev`, built by the apppage engine, a copy of which is in `promo/engine`: texts in `promo/i18n/en.yml`, links and Impressum data in `promo/_config.yml`, colours in `promo/brand.css`, and the privacy policy and terms from `promo/engrossify.yaml`. `promo/compose.yaml` is the Coolify deployment (base directory `/promo`) and names the one secret its build needs. The renderer, the flash page and the docs are on `https://r.espface.manzari.dev`; `promo/renderer-host.conf` redirects their old paths on the landing page host, which firmware 1.0.0 depends on for `/r/1/`.

The images in `promo/images` are generated: `apps/mobile/scripts/promo-shots.sh` renders the app's screens in widget tests, `web/scripts/promo-shots.sh` the renderer in a desktop browser.
