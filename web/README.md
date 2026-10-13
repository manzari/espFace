# espFace web renderer

Vite + Preact + TypeScript. Builds one classic script `dist/r/1/app.js` plus `dist/r/1/app.css`; `app.js` injects its own stylesheet link and mounts into `#app`, which is all the device's bootstrap page provides. The same bundle is served by the hosted site (`server/renderer/`) and, gzipped into flash, by firmware built with `ESPFACE_EMBED_WEB`.

Everything runs in Docker; nothing is installed on the host. `scripts/node.sh` wraps `node:22-alpine` with the repository mounted at `/w` and `web/` as working directory (the tests read `../protocol`).

```
scripts/node.sh npm ci                      # install (commits package-lock.json)
scripts/node.sh npm run build               # tsc + vite build + size report (fails above 80 KB gzipped)
scripts/node.sh npm test                    # Vitest: store and codec against protocol/vectors, HMAC vectors
scripts/e2e.sh                              # Playwright smoke test (fake device + nginx renderer + Playwright, one Docker network)
DOCKER_ARGS="-p 5173:5173" scripts/node.sh npm run dev   # dev server, open http://localhost:5173/?host=localhost:8080
```

Dev against the fake device (from the repository root):

```
docker build -f docker/fake-device.Dockerfile -t espface-fake . && docker run --rm -d --name espface-fake -p 8080:8080 espface-fake --pin=1234
```

## System pages

- OTA push: file picker -> MD5 (pure JS, `src/proto/md5.ts`) -> `ota.begin` -> WebSocket binary frames of 4096 bytes, paused while `bufferedAmount` is above 64 KB -> device `ota.progress`/`ota.done`. Cancel sends `ota.abort`. `ota.url` installs from a URL the device can reach.
- Release check: a button on the info card fetches `https://api.github.com/repos/<repo>/releases/latest` (only when pressed), compares the tag with `fw` and offers the first `.bin` asset to `ota.url`.
- WiFi: `wifi.scan` list with RSSI bars and a lock for encrypted networks, SSID/password form -> `wifi.set`, live `wifi.status` pushes.
- `/flash/`: standalone WebSerial page (Chromium over https) that flashes a `.bin` with esptool-js 0.5.4 loaded from jsdelivr, with a serial monitor. It cannot be exercised headlessly; it is a convenience, not a requirement.

## Connecting

- Served by a device (bootstrap page): connects to `ws://<location.host>/ws`.
- Dev page or hosted landing page (`index.html`, `#app` has `data-dev`): `?host=<host:port>` picks the device and is remembered in `localStorage`; without it the last host is used or a prompt asks for one.
- PIN pairing: HMAC-SHA256 over `nonce + id` with the PIN as key. Web Crypto is used where available; device pages are plain http (insecure context, no `crypto.subtle`), so a small pure-JS SHA-256 fallback is bundled. The session token is stored per device id in `localStorage`.

## Layout

```
src/main.tsx          entry: stylesheet injection, theme, mount
src/app.tsx           chrome: header, page tabs / bottom nav, system view, host prompt
src/session.ts        hello -> auth -> time state machine, reconnect, lockout, token store
src/store.ts          ui model, values, chart/log ring buffers, dialogs, toasts, layout, fine-grained subscriptions
src/proto/            types, codec (c2d builders), hmac
src/transport/ws.ts   WebSocket with backoff
src/widgets/          one component per widget type (registry in index.tsx), unknown types -> "unsupported widget"
src/layout.tsx        pages -> group cards -> rows -> widgets
src/overlays.tsx      toasts, device dialogs, PIN dialog
src/sys/              info (+ GitHub release check), WiFi scan/join, PIN/revoke, reboot, OTA push + URL, console, appearance, connection
src/sys/ota.ts        OTA chunker with socket backpressure, release version compare; src/proto/md5.ts for the image hash
public/flash/         WebSerial flash page (esptool-js from jsdelivr), hosted site only, not part of the bundle
src/icons.tsx         Material Symbols subset as inline SVG
test/                 Vitest; e2e/ Playwright
```

Leaflet (map widget) is loaded from cdnjs only when a map widget is on screen and is not part of the bundle size.

## Bundle size

`npm run build` prints the gzipped size of `app.js` + `app.css` and fails above 80 KB. Current: about 53 KB. `public/flash/` is served next to it and not counted.

## Embedding into firmware

```
scripts/node.sh npm run build
docker run --rm -v "$PWD":/w -w /w/firmware --entrypoint python3 espface-pio tools/embed-web.py   # writes firmware/src/web/embed.h
```
