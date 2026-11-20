# Web renderer

A Vite, Preact and TypeScript renderer that builds to one script `app.js` and one stylesheet `app.css`. The same bundle is gzipped into the firmware, which serves it from flash, and hosted on the renderer site for `/connect/`.

## Served by the device

Every device serves the renderer itself at `/r/1/app.js` and `/r/1/app.css`, so `http://<ip>/` and the captive portal work without internet. The copy costs about 60 KB of flash and no RAM. The browser revalidates it with an ETag, so a reflashed device never runs a stale cached copy.

After changing the renderer, rebuild the web bundle (in `web/`) and run the embed tool from the repository root in the PlatformIO image, which rewrites `firmware/src/web/embed.h`. CI fails when the committed file does not match the build:

```sh
(cd web && scripts/node.sh npm run build)
docker run --rm -v "$PWD":/w -w /w/firmware --entrypoint python3 espface-pio tools/embed-web.py
```

## Bootstrap page

The device serves a roughly 2 KB bootstrap page at `/` (and for the captive-portal probe URLs) that loads `/r/1/app.js` from the device. If that fails, the page shows a short error and suggests reloading or using the app.

## Versioned URLs

The renderer host `https://r.espface.manzari.dev` serves the bundle at `/r/<major>/`, today `/r/1/app.js` and `/r/1/app.css`, with immutable caching and CORS `*`. Firmware 1.0.0 loads the renderer from there; newer firmware serves the same path itself. A breaking change goes to `/r/2/` while `/r/1/` stays for old firmware. The protocol major in `hello` selects the path.

Other URLs of that host:

| URL | Purpose |
|---|---|
| `/` | Landing page |
| `/connect/?host=<host:port>` | Opens the renderer against a device. The old `/?host=` redirects here |
| `/flash/` | WebSerial flash page |
| `/docs/` | Redirects to this documentation on `https://espface.manzari.dev/docs/` |
| `/healthz` | Health check, answers `ok` |

## Settings and storage

Theme settings (accent color, font scale, wide mode) and the session token per device id are stored in `localStorage`. The last host of the hosted page is remembered there too.

## Plain http and the SHA-256 fallback

Device pages are served over http, an insecure context where `crypto.subtle` does not exist. The renderer uses Web Crypto where available and falls back to a bundled pure-JS SHA-256 for the PIN HMAC.

## Bundle budget

`npm run build` prints the gzipped size of `app.js` plus `app.css` and fails above 80 KB. The current size is about 53 KB. Leaflet for the map widget is lazy-loaded from cdnjs and not counted. The flash page is served next to the bundle and not counted either.

## Self-hosting with Coolify

1. Create a new resource of type Docker Compose from the git repository.
   - Base directory: `/` (the Dockerfile needs `web/` and `protocol/` in the build context).
   - Docker Compose location: `/server/renderer/docker-compose.yml`.
2. Set the domain on the service. Coolify fills `SERVICE_FQDN_RENDERER_80` from it. No ports are published; Traefik terminates TLS and proxies to port 80.
3. Deploy. The container is healthy when `GET /healthz` answers `ok`.
4. Open devices through `https://your.host/connect/?host=<host:port>`.

The image builds with `npm ci && npm run build` inside Docker, so nothing is built on the host.

## Run locally

```sh
docker build -f server/renderer/Dockerfile -t espface-renderer .
docker run --rm -p 8081:80 espface-renderer
# http://localhost:8081/connect/?host=localhost:8080   (with the fake device running)

```

The Node wrapper runs from `web/`:

```sh
cd web
scripts/node.sh npm ci
scripts/node.sh npm test
DOCKER_ARGS="-p 5173:5173" scripts/node.sh npm run dev
```

## Reconnect behaviour

Same as the app: exponential backoff of 500 ms times 2^n with 25 % jitter, capped at 30 s, "retry now" and "Forget pairing and reconnect" act immediately, the stored token skips the PIN, and the last UI stays under a "Connection lost, reconnecting in N s" banner. A device that answers err 9 shows "Device is full (too many clients), retrying"; the lockout dialog counts down live; err 5 after a correct PIN is retried once. Buffers are bounded: 5000 chart points per series, 2000 log lines, 500 console lines, 5 toasts, 10 dialogs.
