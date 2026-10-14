# Security model

## Threat model

espFace is designed for a trusted local network, a BLE radio within reach, or a wired stream. There is no TLS and no transport encryption. The protocol protects the PIN, not the traffic: anyone who can sniff the network can read values and events in flight, and can read a session token when one is sent.

If you need more, wrap the transport (a VPN) rather than the protocol. A later cloud relay will carry the same protocol over TLS.

## PIN challenge-response

A device with a PIN sends `auth: "pin"`, `ok: false` and a fresh random 16-byte nonce (32 lowercase hex characters) in its `hello`. The client answers with

```text
mac = HMAC-SHA256(key = PIN as UTF-8 bytes, msg = nonce_hex + device_id)
```

where `nonce_hex` is the 32-character string exactly as received, `device_id` is the `id` from the same hello and `mac` is sent as 64 lowercase hex characters. The nonce changes on every hello, so a captured answer is useless for replay.

Test vector:

| Input | Value |
|---|---|
| PIN | `1234` |
| nonce | `00112233445566778899aabbccddeeff` |
| device id | `a1b2c3` |
| mac | `03cc85f2b0409c8d81d2648f5f68c212d8feea811ba59f01908e213163e596a8` |

A device without a PIN answers `ok:true` to every hello and sends no nonce or token.

## Tokens

After a correct answer the device returns a 32-character hex session token. The client stores it per device id (secure storage in the app, `localStorage` in the web renderer) and sends it in later hellos to skip the PIN. Tokens never expire. They are deleted by `revoke` and by `pin.set`; both also drop every other session. A client whose token was revoked sees the PIN dialog again.

The token does travel in clear, which is why the model is "trusted network".

## Lockout

Five wrong answers trigger a 60 second lockout. The device then refuses `auth` and reports the remaining seconds in `lock`, also in a `hello` during the lockout. Clients show a live countdown.

## Per-UI PIN

Each UI can have its own PIN: `ui.pin("")` makes a UI open, `ui.pin("9999")` sets another one, and `face.setPin()` applies to the default UI. A common setup is an open provisioning UI on BLE and a PIN-protected main UI on WiFi. See [Concepts](/guide/concepts).

## Capabilities are opt-in

System features only exist when the sketch enables them. OTA is off by default; without `face.enableOta(true)` the device answers OTA commands with err 8 and `POST /update` does not exist. With a PIN set, `POST /update` requires a valid session token. The same applies to PIN management, WiFi provisioning and ntfy.

## What travels in clear

- Widget values, events, log lines and chart data.
- The session token, in `hello` and in `?tok=` on `/update`.
- WiFi credentials sent through `wifi.set`.
- OTA images.

The PIN is never sent.

## Recommendations

- Use a PIN on every device that does something physical.
- Keep the device on a trusted or isolated network, or reach it through a VPN.
- Change the PIN to revoke all tokens when a phone is lost.
- Set `setOtaCaCert()` if you download updates or send ntfy over https; otherwise TLS is unverified.
