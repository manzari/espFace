# espFace web renderer

Vite + Preact + TypeScript. Builds one classic script `dist/r/1/app.js` plus `dist/r/1/app.css`; `app.js` injects its own stylesheet link and mounts into `#app`, which is all the device's bootstrap page provides. The same bundle is served by the hosted site (`server/renderer/`) and, gzipped into flash, by firmware built with `ESPFACE_EMBED_WEB`.

Everything runs in Docker; nothing is installed on the host. `scripts/node.sh` wraps `node:22-alpine` with the repository mounted at `/w` and `web/` as working directory (the tests read `../protocol`).

```
scripts/node.sh npm ci                      # install (commits package-lock.json)
scripts/node.sh npm run build               # tsc + vite build + size report (fails above 80 KB gzipped)
scripts/node.sh npm test                    # Vitest: store/codec/OTA against protocol/vectors, icons vs the app, hardening against the in-process fake device
scripts/e2e.sh                              # Playwright: smoke + hardening (seven fake devices with knobs + nginx renderer + Playwright, one Docker network)
scripts/node.sh npm run icons               # regenerates src/icons-paths.ts from src/icons.json (commit the result)
scripts/widget-shots.sh                     # docs widget screenshots, light + dark, into docs/site/public/widgets (commit the result)
DOCKER_ARGS="-p 5173:5173" scripts/node.sh npm run dev   # dev server, open http://localhost:5173/connect/?host=localhost:18080
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
- Dev page or hosted connect page (`connect/index.html`, `#app` has `data-dev`): `/connect/?host=<host:port>` picks the device and is remembered in `localStorage`; without it the last host is used or a prompt asks for one. The hosted root `/` is a static landing page (`public/index.html`) linking the docs, the flash page and the connect form; `/?host=` redirects to `/connect/`.
- PIN pairing: HMAC-SHA256 over `nonce + id` with the PIN as key. Web Crypto is used where available; device pages are plain http (insecure context, no `crypto.subtle`), so a small pure-JS SHA-256 fallback is bundled. The session token is stored per device id in `localStorage`.

## Reconnecting (phase 6)

- `transport/ws.ts`: exponential backoff 500 ms × 2^n with ±25 % jitter, capped at 30 s (`backoffDelay`); `reconnect(0)` is immediate and resets the backoff; `pause()`/`resume()` stop retries while the tab is hidden.
- The UI model is kept while offline (`store.reset()` only drops per-connection state); the banner shows "Connection lost, reconnecting in N s" with a retry link, or "Device is full" after `err` 9 on hello.
- The stored token resumes the session; a wrong/revoked token falls back to the PIN dialog; lockout shows a countdown; `err` 5 after a correct PIN is retried once with a fresh nonce.
- Bounds: chart series ≤ 5000 points (and `win`), log widgets ≤ 2000 lines (and `cap`), console 500, toasts 5, dialogs 10; buffers of widgets missing from a new `ui` are released; `subscribe()` drops empty listener sets.
- `window.espface` exposes `store` and `session` for tests and debugging; `store.listenerCount()` and `session.ws.attempts` feed the leak test.

Measured (Chromium in Playwright, `scripts/e2e.sh`): see the `huge-ui` and `1000 reconnects` tests, which print widget counts, render times, listener counts and heap before/after.

## Icons

`src/icons.json` is the shared subset (Material Icons, filled): keys are the names sketches use, values the icon file names. `npm run icons` writes `src/icons-paths.ts` from `@material-design-icons/svg`; `test/icons.test.ts` checks that the app's `icons.dart` maps exactly the same names and that both use `help_outline` as the fallback.

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
src/icons.tsx         shared icon subset as inline SVG (src/icons.json -> generated src/icons-paths.ts)
test/                 Vitest (store, codec, ota, icons, hardening); e2e/ Playwright (smoke, hardening)
```

Leaflet (map widget) is loaded from cdnjs only when a map widget is on screen and is not part of the bundle size.

## Bundle size

`npm run build` prints the gzipped size of `app.js` + `app.css` and fails above 80 KB. Current: about 53 KB. `public/flash/` is served next to it and not counted.

## Embedding into firmware

```
scripts/node.sh npm run build
docker run --rm -v "$PWD":/w -w /w/firmware --entrypoint python3 espface-pio tools/embed-web.py   # writes firmware/src/web/embed.h
```
