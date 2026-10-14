# Fake device

`tools/fake-device` is a Node implementation of the device side of protocol v1. Use it to develop and test the web renderer and the app without hardware, to reproduce bad networks, and as a reference while writing firmware.

## Run it

With Docker, from the repository root:

```sh
docker build -f docker/fake-device.Dockerfile -t espface-fake .
docker run --rm -p 18080:8080 espface-fake --pin=1234 --drop-every 8
```

Host port 8080 is often taken, so the example maps 18080. Clients connect to `ws://<host>:18080/ws`.

With Node, inside `tools/fake-device`:

```sh
npm install
npm start -- --port=8080 --pin=1234
npm test
```

## Flags

Flags accept `--k=v` and `--k v`.

| Flag | Meaning |
|---|---|
| `--port=N` | Listen port (default 8080, or the `PORT` environment variable) |
| `--pin=1234` | Require a PIN; without it the device is open |
| `--name=Boiler` | Display name |
| `--id=a1b2c3` | Device id |
| `--no-sim` | Disable the simulated sensor data |
| `--drop-every N` | Close the socket with code 4000 after every N device-to-client messages |
| `--latency ms` | Delay messages by this many ms in both directions |
| `--slow-ui` | Send `ui` as many small WebSocket fragments with delays |
| `--max-clients N` | An extra client gets err 9 and is closed |
| `--flaky-auth` | Answer the first correct auth with err 5 once; the client must hello again and retry |
| `--huge-ui[=N]` | Demo UI plus N generated widgets (default 400) over extra pages and groups, about 100 KB. The schema caps `ui.w` at 500 |
| `--help` | Print usage |

## Demo UI

The demo uses every widget type across three pages ("Boiler", "I/O", "Setup"). It streams chart points and log lines, opens a confirm dialog from Erase and a prompt from Rename, flips props (color and label of the gauge) when the simulated temperature exceeds 85 °C and shows a toast. System side: WiFi scan and set, info, reboot, PIN change, token revoke, OTA push with MD5 check and OTA by URL.

## Using it for tests

- **Web unit tests** run the fake device in-process: `scripts/node.sh npm test` (from `web/`).
- **Web e2e**: `scripts/e2e.sh` (from `web/`) starts seven fake devices with different knobs, the nginx renderer and Playwright in one Docker network.
- **App tests**: `scripts/flutter.sh test` (from `apps/mobile/`). The integration tests are skipped unless one of these is set: `ESPFACE_FAKE_WS`, `ESPFACE_FAKE_WS_DROP`, `ESPFACE_FAKE_WS_SLOW`, `ESPFACE_FAKE_WS_HUGE`, `ESPFACE_FAKE_WS_BUSY`, `ESPFACE_FAKE_WS_FLAKY`. For example:

```sh
ESPFACE_FAKE_WS=ws://host.docker.internal:18080/ws scripts/flutter.sh test test/integration/fake_device_test.dart
```

## As a firmware reference

When a widget behaves oddly on the real device, run the fake device with the same UI and compare the message flow. The fake device is checked against the same schema and vectors as the firmware, so any difference in what goes over the wire is a bug in one of them. See [Protocol v1](/protocol/).
