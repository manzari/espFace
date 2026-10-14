# Contributing and CI

## Repository layout

```text
espFace/
  protocol/      JSON schema v1, PROTOCOL.md, test vectors (single source of truth)
  firmware/      Arduino library: src/, examples/, test/ (native), tools/ (embed-web.py, ci-build.sh)
  web/           TypeScript renderer (Vite + Preact)
  apps/mobile/   Flutter app
  tools/fake-device/   Node implementation of the device side
  docker/        Dockerfiles: platformio, flutter, fake-device
  server/        renderer hosting (nginx image, Coolify compose)
  docs/          PLAN.md and this site (docs/site)
```

## Everything runs in Docker

Nothing is installed on the host. From the repository root:

```sh
# protocol: schema and vectors
docker run --rm -v "$PWD":/w -w /w/protocol node:22-alpine sh -c "npm install && npm test"

# firmware: native unit tests, then ESP32 builds plus footprint.md
docker build -f docker/platformio.Dockerfile -t espface-pio .
docker volume create espface-pio
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware espface-pio test -e native
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware --entrypoint sh espface-pio tools/ci-build.sh

# web renderer (from web/)
cd web
scripts/node.sh npm ci
scripts/node.sh npm run build
scripts/node.sh npm test
scripts/e2e.sh
cd ..

# mobile app (from apps/mobile/)
cd apps/mobile
scripts/flutter.sh pub get
scripts/flutter.sh analyze
scripts/flutter.sh test
scripts/flutter.sh build apk --debug
cd ../..

# this docs site
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine npm ci
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine npm run build
```

The wrappers `node.sh` and `e2e.sh` live in `web/scripts/`, `flutter.sh` in `apps/mobile/scripts/`. The docs dev server runs the `dev` script the same way with `-p 5174:5173`.

## CI

Forgejo Actions in `.forgejo/workflows/ci.yml`:

| Job | What it does |
|---|---|
| protocol | Schema vectors and fake device tests |
| firmware-native | PlatformIO native tests; output validated against the schema |
| firmware-esp32 | Example build matrix plus footprint report |
| flutter | analyze, test, integration tests against the fake devices, debug APK |
| web | build plus Vitest |
| docs | builds this site |

## Changing the protocol

The protocol is the contract between three implementations, so a change touches all of them in one pull request:

1. Edit `protocol/PROTOCOL.md` and the schema in `protocol/schema/v1`.
2. Add or update vectors in `protocol/vectors`.
3. Update the firmware, the web renderer and the Flutter app, and the fake device.
4. Additions within a major are backwards compatible through the ignore-unknown rule. Removing or retyping a field needs a new major and a new `/r/<major>/` path.

## Phases

| Phase | State |
|---|---|
| 0 Protocol | done |
| 1, 1b Firmware core and extended widgets | done |
| 2 Web renderer | done |
| 3 App over WiFi | done |
| 4 System pages | done |
| 5 BLE and streams | done |
| 6 Hardening and docs | done |
| 7 Release (Library Manager, PlatformIO registry, stores, renderer v1 frozen) | next |
| 8 Relay (`RelayTransport`, self-hostable relay server) | later |

## Licence

MIT for the library, the web renderer and the apps.
