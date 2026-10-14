# espFace fake device

Node implementation of the device side of espFace protocol v1. Use it to develop and test the web renderer and the apps without hardware, and as the reference while the firmware is written.

```
npm install
npm start -- --port=8080 --pin=1234      # pin optional; --no-sim disables simulated sensor data
npm test                                  # needs ../../protocol installed (npm install there) for the schema
```

Or with Docker from the repository root:

```
docker build -f docker/fake-device.Dockerfile -t espface-fake .
docker run --rm -p 8080:8080 espface-fake --pin=1234
```

## Hardening knobs

Flags to simulate bad networks and device limits (`--k=v` and `--k v` both work); used by the web and app hardening tests:

| Flag | Effect |
|---|---|
| `--drop-every N` | closes the socket (code 4000) after every N device→client messages; the next connection is served again |
| `--latency ms` | delays every message by `ms` in both directions (round trip 2 × ms) |
| `--slow-ui` | sends the `ui` message as many small WebSocket fragments (512 bytes, 20 ms apart); other messages queue behind it |
| `--max-clients N` | the N+1th `hello` is answered with `err` 9 and closed (default 4) |
| `--flaky-auth` | the first correct `auth` is answered with `err` 5 once; the client must send a new `hello` and retry |
| `--huge-ui[=N]` | demo UI plus N (default 400) generated widgets over extra pages and groups, about 100 KB of JSON (the schema caps `ui.w` at 500 entries) |

```
docker run --rm -p 18080:8080 espface-fake --pin=1234 --drop-every 8 --latency 50
```

`npm test` runs `test/smoke.mjs` (full session, every device message schema-checked) and `test/knobs.mjs` (one scenario per knob plus CLI parsing).

Clients connect to `ws://<host>:8080/ws`. The demo UI uses every widget type across three pages, streams chart points and log lines, opens dialogs from the Erase and Rename buttons, flips props when the simulated temperature exceeds 85 °C, and implements WiFi scan/set, info, reboot, PIN change, token revoke, OTA push with MD5 check and OTA by URL.
