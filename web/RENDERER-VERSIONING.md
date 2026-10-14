# Renderer versioning: `/r/1/` is frozen

Devices do not ship the web renderer. Their bootstrap page (`firmware/src/web/bootstrap.h`) loads
`ESPFACE_RENDERER_HOST + "/r/1/app.js"` (default `https://espface.manzari.dev/r/1/app.js`), and that URL is baked into
every firmware ever flashed. Devices stay in the field for years without updates, so the hosted path is a contract.

## Rules

1. **One path per protocol major.** `/r/1/` serves protocol v1. A protocol v2 (a breaking change by
   `protocol/PROTOCOL.md` section 6) gets a new bundle at `/r/2/`; the bootstrap of v2 firmware points there.
2. **`/r/1/` only receives backward-compatible changes.** Bug fixes, styling, performance, and additions allowed within
   a major (new widget types, props, `sys` commands, caps, which old devices never send). Never remove or reinterpret
   handling of a v1 message, widget type, prop or value encoding.
3. **Old paths are never removed.** `/r/1/` stays online after `/r/2/` exists. Moving hosts means serving the same paths
   on the old domain (or a permanent redirect that keeps CORS headers) for as long as v1 devices may exist.
4. **File names are stable.** `/r/1/app.js` and `/r/1/app.css` (no content hashes) because the device page references
   them literally.
5. **Headers stay as they are** (`server/renderer/nginx.conf`, `location /r/`): `Cache-Control: public, max-age=31536000,
   immutable`, `Access-Control-Allow-Origin: *`, `Cross-Origin-Resource-Policy: cross-origin`. Browsers may keep a
   cached copy for a year, which is why changes under `/r/1/` must be safe to mix with older cached copies.
6. **The renderer version** (`web/package.json`, shown in the system page footer) is independent of the path: renderer
   1.0.0, 1.1.0, 1.2.0 and so on are all served at `/r/1/`. Versions never contain the digit 4.

## Freeze gate (CI)

`npm run freeze` in `web/` (CI job `renderer-v1-freeze` in `.forgejo/workflows/ci.yml`) fails when a build drops v1
support:

- `test/freeze.test.ts`: all 30 widget types from `protocol/PROTOCOL.md` section 5.2 have a renderer component (layout
  types build pages, groups and rows); every d2c message type in the v1 schema has a vector that decodes and is handled
  by the store (`auth` by the session); the client can still build every c2d message type.
- `scripts/freeze-check.mjs` on the built `dist/`: `r/1/app.js`, `r/1/app.css`, `connect/index.html` and `index.html`
  exist, and every widget and message type name is still present in the bundle.

Together with `test/store.test.ts` (every d2c vector applied without throwing) and `test/codec.test.ts` (every c2d
message validates against the schema) this is the contract. Changing it requires a protocol major bump, not an edit
of the gate.

## Releasing a renderer change

1. Change, `npm run build && npm test && npm run freeze`.
2. Bump `web/package.json` together with the other components (`tools/release/check-versions.sh`).
3. Deploy the renderer image (`docs/RELEASE.md`, renderer section). Users see the change once their cached copy expires
   or on a hard reload; nothing on the device changes.
