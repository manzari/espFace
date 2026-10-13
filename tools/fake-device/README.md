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

Clients connect to `ws://<host>:8080/ws`. The demo UI uses every widget type across three pages, streams chart points and log lines, opens dialogs from the Erase and Rename buttons, flips props when the simulated temperature exceeds 85 °C, and implements WiFi scan/set, info, reboot, PIN change, token revoke, OTA push with MD5 check and OTA by URL.
