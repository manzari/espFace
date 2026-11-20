# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

espFace is a monorepo. An ESP32 sketch describes a control UI with the Arduino library (`firmware/`). Three clients draw it over one JSON protocol (`protocol/PROTOCOL.md`): the Preact web renderer (`web/`), the Flutter app (`apps/mobile/`), and a Node fake device (`tools/fake-device/`). The fake device is the reference device-side implementation that every client test runs against. Design rationale: `docs/PLAN.md`. Release steps: `docs/RELEASE.md`.

## Commands (everything runs in Docker; install nothing on the host)

Run these from the repository root unless a line says otherwise.

```sh
# protocol schema + vectors
docker run --rm -v "$PWD":/w -w /w/protocol node:22-alpine sh -c "npm ci && npm test"

# fake device on ws://localhost:18080/ws (host 8080 is often taken); knobs: --drop-every N --latency ms --slow-ui --huge-ui --max-clients N --flaky-auth
docker build -f docker/fake-device.Dockerfile -t espface-fake . && docker run --rm -p 18080:8080 espface-fake --pin=1234

# firmware: native unit tests (ASAN), then the ESP32 example x board matrix + footprint.md
docker build -f docker/platformio.Dockerfile -t espface-pio . && docker volume create espface-pio
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware espface-pio test -e native
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware --entrypoint sh espface-pio tools/ci-build.sh [board ...]

# web (from web/): scripts/node.sh = node:22-alpine with the repo mounted at /w
scripts/node.sh npm ci
scripts/node.sh npm run build                             # tsc + vite + size gate (fails above 80 KB gzipped)
scripts/node.sh npm test                                  # Vitest
scripts/node.sh npx vitest run test/store.test.ts -t "name"   # single test
scripts/node.sh npm run freeze                            # /r/1/ freeze gate (needs a build)
scripts/e2e.sh [e2e/smoke.spec.ts -g "name"]              # Playwright: 7 fake devices + nginx renderer on one network
DOCKER_ARGS="-p 5173:5173" scripts/node.sh npm run dev    # http://localhost:5173/connect/?host=localhost:18080

# mobile (from apps/mobile/): scripts/flutter.sh runs inside FLUTTER_IMAGE (default inhumane-flutter:latest; docker/flutter.Dockerfile is equivalent)
scripts/flutter.sh pub get
scripts/flutter.sh analyze
scripts/flutter.sh test
scripts/flutter.sh test test/codec_test.dart --plain-name "name"   # single test
ESPFACE_FAKE_WS=ws://host.docker.internal:18080/ws scripts/flutter.sh test test/integration/fake_device_test.dart
FLUTTER_CMD=dart scripts/flutter.sh format lib test
scripts/flutter.sh build apk --debug

# docs site (VitePress; regenerates the API reference from firmware headers first)
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/w -w /w/docs/site node:22-alpine sh -c "npm ci && npm run build"

# hosted image: renderer + /flash/ (this is what Coolify deploys at r.espface.manzari.dev)
docker build -f server/renderer/Dockerfile -t espface-renderer . && docker run --rm -p 8081:80 espface-renderer

# landing page + /docs/ (promo/, its own Coolify resource at espface.manzari.dev): local preview with placeholder legal pages, then its screenshots
docker build --build-arg ALLOW_PLACEHOLDER_LEGAL=1 -f promo/Dockerfile -t espface-promo . && docker run --rm -p 8888:80 espface-promo
apps/mobile/scripts/promo-shots.sh                        # promo/images/phone-*.jpg
web/scripts/promo-shots.sh                                # promo/images/web-*.jpg
```

Notes on testing:
- Firmware native tests live in one file, `firmware/test/test_core/test_main.cpp`, and run as one Unity suite. A new test needs a `RUN_TEST` line in `main`. The suite writes every D→C message to `firmware/test_output/d2c.jsonl`. CI then checks that file against the schema with `cd protocol && node test/validate.mjs --d2c ../firmware/test_output/d2c.jsonl`.
- Flutter integration tests skip unless their env var is set: `ESPFACE_FAKE_WS`, plus one var per knob in `ESPFACE_FAKE_WS_{DROP,SLOW,HUGE,BUSY,FLAKY}`. Plain `flutter test` stays offline.
- Web Vitest reads `../protocol` (schema and vectors). The web hardening test starts `tools/fake-device` in-process, which is why `ws` is aliased in `vite.config.ts`.
- BLE, USB, and SPP radios have no CI coverage. Their transports are tested against fakes.

## Architecture

**The protocol is the single source of truth.** `protocol/schema/v1/*.schema.json` and `protocol/vectors/*.json` are shared test data. The firmware validates its output against the schema. Web (`test/codec.test.ts`, `store.test.ts`) and mobile (`codec_test.dart`) decode every vector. Rules that every side follows: unknown keys, message types, and widget types are ignored (an unknown widget renders as "unsupported widget"), and ids match `^[A-Za-z0-9_]{1,15}$` so a widget id can double as an NVS key.

**Changing the protocol or adding a widget type** touches every implementation in one change:
1. `protocol/PROTOCOL.md` (§5.2 lists the widget types), the schema, and the vectors.
2. Firmware: builder in `src/ui/Ui.h`, README table, `docs/site/scripts/api-notes.json`.
3. Web: component in `src/widgets/` plus the registry in `src/widgets/index.tsx`.
4. Mobile: widget plus `lib/features/render/widgets/registry.dart`.
5. Fake device: `src/demo-ui.mjs`.

Additions within v1 are fine because of the ignore-unknown rule. Removing or retyping anything requires protocol v2 and a new `/r/2/` path.

**`/r/1/` is a frozen contract** (`web/RENDERER-VERSIONING.md`). The device serves the renderer from its own flash: the bootstrap page (`firmware/src/web/bootstrap.h`) loads `/r/1/app.js` from the device, which serves the gzipped bundle in `firmware/src/web/embed.h`. Devices flashed with firmware 1.0.0 instead load `https://espface.manzari.dev/r/1/app.js` literally, for years, with year-long immutable caching. That host is the landing page now; `promo/renderer-host.conf` redirects `/r/`, `/connect/` and `/flash/` to the renderer host `https://r.espface.manzari.dev`, and that redirect must stay. The docs site is built into the landing page image and served at `https://espface.manzari.dev/docs/` (`promo/docs.conf`); the renderer host redirects its old `/docs/` there. That means:
- Web builds one IIFE bundle with fixed file names and no hashes.
- Changes must be backward compatible and must be safe to mix with older cached copies.
- `npm run freeze` (`test/freeze.test.ts` + `scripts/freeze-check.mjs`) fails if any v1 widget or message type is dropped. Never edit the gate to make it pass.

**Firmware layering** (`firmware/src/`):
- `core/Core` is platform independent: sessions, auth/tokens/lockout (`proto/Session`), message dispatch, and multiple UIs.
- `ui/Ui` is the builder plus values, dirty masks, and persistence.
- `transport/*` implements `Transport` (`sendFrame(slot, data, len, first, last)`). The core streams large messages through `FrameSink` without building them in RAM.
- `Face.h`/`Face.cpp` (`EspFace`) is the Arduino facade that wires the core to NVS, WiFi, OTA, NTP, ntfy, and the transports.
- `Platform.h` switches `Str` between Arduino `String` and `std::string` on `ARDUINO`. It also holds every `ESPFACE_*` compile-time default.
- ESP-only code sits behind `#ifdef ARDUINO` or in separate `*Esp.cpp` files (`OtaEsp`, `NtfyEsp`), so the logic in `Ota.cpp`/`Ntfy.cpp` still builds natively.
- The `native` env in `platformio.ini` excludes `Face.cpp`, the WS/BLE/BT transports, `WifiMgr`, and `NvsStore`. Tests use `MemStore` and a `MemTransport`.

Firmware constraints:
- The library builds with `-fno-exceptions` (`library.json`).
- `Face.h` methods such as `enableOta()` and `ntfy()` are deliberately inline, so HTTPClient, Update, and TLS link only when a sketch calls them.
- CI fails when Minimal's flash delta on esp32dev exceeds `firmware/footprint.budget`.
- Per-example build tweaks go in `examples/<name>/{build_flags,lib_deps,boards,project_options}`. Per-board tweaks go in `tools/boards/<board>.{flags,options,platform}`.
- The ESP32-C6 build depends on the pioarduino fork and is allowed to fail.

**Clients mirror each other.**
- Structure: web `session.ts`/`store.ts`/`transport/ws.ts` correspond to mobile `core/session`, `features/render/ui_store.dart`, and `core/transport/`. Both use a hello → auth → time state machine, the same jittered backoff (500 ms × 2ⁿ, ±25 %, capped at 30 s), and the same buffer bounds.
- Mobile transport mirrors firmware: `ble_framer.dart` mirrors firmware `BleFramer.h`, and `line_framer.dart` mirrors `LineFramer.h`. Keep each pair behaviourally identical.
- Icons: `web/src/icons.json` is the shared icon subset. `npm run icons` regenerates `src/icons-paths.ts`, and `web/test/icons.test.ts` checks that mobile `lib/features/render/icons.dart` maps exactly the same names.

**Generated, committed files** (regenerate them; do not hand-edit):
- `firmware/src/web/embed.h`: run `tools/embed-web.py` after a web build. Always compiled in; CI fails when it does not match the web build.
- `web/src/icons-paths.ts`
- `docs/site/public/widgets/*`: run `web/scripts/widget-shots.sh`.
- Mobile store screenshots and icons: `apps/mobile/scripts/{screenshots,icons}.sh`.
- `promo/images/{phone,web}-*.jpg`: run the two `promo-shots.sh` scripts. `test/screenshots_test.dart` serves both the store set and the promo set.
- `promo/engine/`: a copy of the apppage engine (`git.hauptstadt.monster/manzari/apppage`). Change the engine there and copy it again; the page's own content is everything else in `promo/`.

The docs build also generates gitignored files: `reference/*.md` from `Face.h`, `Ui.h`, and the firmware README; `protocol/index.md`; and `guide/icons-list.md`.

## Versioning and conventions

- All component versions move in lockstep and **never contain the digit 4** (0.3.0 → 0.5.0, 1.3.x → 1.5.0; Android versionCodes too). `tools/release/check-versions.sh [vX.Y.Z]` checks `firmware/library.properties`, `library.json`, `ESPFACE_LIB_VERSION` in `Platform.h`, and `web/`, `tools/fake-device/`, `docs/site/` `package.json`. Tag `v*` triggers `.forgejo/workflows/release.yml`.
- CI is Forgejo Actions (`.forgejo/workflows/ci.yml`). Releases are cut from the monorepo; `tools/release/split-library.sh` exports `firmware/` as the standalone Arduino library.
- Commit subjects use the form `<component>: <summary>`. Components: `firmware`, `web`, `app`/`mobile`, `docs`, `promo`, `fake-device`, `ci`, `release`.
- Dependencies are pinned to exact versions. Mobile stays FOSS-only. For example, `flutter_blue_plus` is pinned at 1.36.8 (the last BSD release), and `usb_serial` is vendored under `third_party/` with a Gradle 9 build file.
- `CHANGELOG.md` (Keep a Changelog) at the root, plus `firmware/CHANGELOG.md` for the library registries.
