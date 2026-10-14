# Mobile app

A Flutter app for Android and iOS that renders any espFace device natively. It needs no account and no internet.

## Install

| Channel | State |
|---|---|
| Google Play | planned, phase 7 |
| App Store | planned, phase 7 |
| F-Droid | planned, phase 7 (own repository) |
| Debug APK | built by every CI run (job `flutter`), install with `adb install app-debug.apk` |

The app id is `dev.manzari.espFace`.

## Device list

Saved devices are grouped by the project name the sketch sets with `face.setProject("Home")`, can be reordered by dragging and show the icon from `face.setIcon()`. A device can hold several addresses (WiFi, BLE, USB, Bluetooth) at once.

## Adding devices

- **mDNS**: devices on the same WiFi are found through `_espface._tcp`.
- **BLE scan**: filtered on the espFace service UUID; the name and id are read without opening a session.
- **QR code**: scans an `espface://` link.
- **Manual**: enter `host[:port]`.
- **USB OTG and Bluetooth Classic** (Android only): list available serial adapters and paired SPP devices.

## Pairing

If the device has a PIN, the app shows a PIN dialog on first connect and stores the session token in secure storage. Later connections resume without a prompt. A lockout dialog shows a live countdown. See [Security model](/guide/security).

## Transports

The app tries the saved addresses in order WiFi, BLE, serial and remembers what worked. Pin one per device with "Preferred transport" in the System page. BLE, USB and SPP have no binary frames, so the OTA section hides the push half and keeps `ota.url`. USB baud rate is selectable per device (default 115200). See [Transports](/guide/transports).

## System page

Per device, depending on its capabilities: info (version, about, reset reason, heap, IP), WiFi scan and join, PIN change and revoke, reboot, OTA push or URL, optional GitHub release check, console, and the connection section with transport pin.

## Theme and offline use

Settings cover dynamic color, accent color, font scale and a wide layout. The app is offline by design: it only contacts the internet for the user-triggered release check (off by default) and map tiles of the `map` widget.

## White-label builds

Everything is a `--dart-define`; no fork is needed.

| Define | Effect |
|---|---|
| `ESPFACE_APP_NAME=AcmeCtl` | Title in the app (the Android label stays `espFace` unless `strings.xml` is changed too) |
| `ESPFACE_ACCENT=#112233` | Fixed seed color; disables dynamic color and the accent setting |
| `ESPFACE_PROJ=Acme` | Only devices with this `proj` are listed and discovered |
| `ESPFACE_DEVICES=Boiler@10.0.0.5,Pump@pump.local:8080` | Locked device list: no add, remove or reorder |
| `ESPFACE_RELEASE_CHECK=on` | Enable the (still user-triggered) release check by default |

```sh
scripts/flutter.sh build apk --debug \
  --dart-define=ESPFACE_APP_NAME=AcmeCtl \
  --dart-define=ESPFACE_ACCENT=#112233 \
  --dart-define=ESPFACE_PROJ=Acme
```

## iOS notes

- iOS asks for the local network permission on first discovery. If you deny it, mDNS and direct connections fail until you allow it in Settings.
- Bonjour service `_espface._tcp` is declared in Info.plist.
- USB serial and Bluetooth Classic do not exist on iOS and are hidden. BLE works.
- Building and signing needs a Mac.

## Reconnect behaviour

When the connection drops, the last known UI stays on screen under a "Connection lost, reconnecting in N s" banner. The app retries with exponential backoff: 500 ms times 2^n with 25 % jitter either way, capped at 30 s. The stored token resumes the session without a PIN prompt. "Retry now" and "Forget pairing and reconnect" reconnect immediately.

Special cases: a device that answers err 9 shows "Device is full (too many clients), retrying"; err 5 after a correct PIN is retried once automatically. While the app is in the background it pauses reconnect attempts and reconnects immediately when it returns to the foreground.

Client buffers are bounded: chart series keep at most 5000 points (and the widget's `win`), log widgets 2000 lines (and the widget's `cap`, default 200), the console 500 lines, toasts 5 and dialogs 10.
