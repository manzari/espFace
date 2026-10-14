# Privacy policy

This policy covers the espFace mobile app for Android and iOS (`dev.manzari.espface` / `dev.manzari.espFace`) and the espFace web renderer served by your own devices. Last updated 2026-10-14.

## Summary

espFace collects no personal data. It has no accounts, no analytics, no crash reporting, no advertising and no tracking. Nothing you do in the app is sent to the developer or to any third party.

## What the app talks to

| Destination | When | What is sent |
|---|---|---|
| Your espFace devices | When you open or add a device | The espFace protocol over your local network (WebSocket), Bluetooth LE, Bluetooth Classic or a USB cable: widget values, events, and on pairing an HMAC proof of the PIN (never the PIN itself) |
| Local network (mDNS) | While the "add device" sheet is open | A query for `_espface._tcp` services |
| OpenStreetMap tile servers | Only when a device shows a `map` widget | Standard HTTPS tile requests (your IP address and the map area, as with any map). See the [OSM Foundation privacy policy](https://osmfoundation.org/wiki/Privacy_Policy) |
| GitHub API (`api.github.com`) | Only when you enable the firmware release check in Settings (off by default) and tap "Check GitHub" on a device's system page | One request for the latest release of the repository the device reports. "Install" then hands the release's download URL to the device, which fetches the firmware itself. See [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) |
| A URL you enter or a device names | Only when you start an OTA update from a URL (the device downloads it), or a device shows an `image`/`stream` widget (the app loads it) | A plain request to that URL |

No other network connections are made.

## What is stored on your phone

- The list of devices you added (name, address, project, icon), and your theme settings, in the app's private storage.
- Session tokens issued by PIN-protected devices, in the platform's secure storage (Android Keystore / iOS Keychain).

This data never leaves your phone, except that a token is sent back to the device that issued it. Uninstalling the app removes it; "Forget pairing" and "Remove" in the device menu delete it per device.

## Permissions

| Permission | Why |
|---|---|
| Network access, Wi-Fi state, multicast | Connect to devices on your local network and discover them via mDNS |
| Bluetooth (scan, connect) | Find and connect to devices over Bluetooth LE and Bluetooth Classic. On Android 12 and newer the scan is declared `neverForLocation`: the app does not derive your location |
| Location (Android 11 and older only) | Android requires it for any Bluetooth scan on these versions. The app never reads your location |
| Camera (optional) | Scan a device's QR code to add it. Images are processed on the phone and not stored |
| USB host (optional, Android) | Talk to ESP32 boards plugged in with an OTG cable |
| Local network (iOS) | Same as network access above |

You can deny any of these; only the matching feature stops working.

## Children

The app is a technical tool and is not directed at children. It collects no data from anyone.

## Changes

Changes to this policy are published on this page and in the project's repository.

## Contact

Questions: open an issue at [git.hauptstadt.monster/manzari/espFace](https://git.hauptstadt.monster/manzari/espFace/issues) or write to mail@manzari.dev.
