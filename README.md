# espFace

An ESP32 describes its control UI in a few lines of Arduino code; native Android/iOS apps and a web renderer draw it. Plan: `docs/PLAN.md`. Protocol: `protocol/PROTOCOL.md`.

```
protocol/           JSON schema v1, test vectors, validator      (phase 0, done)
tools/fake-device/  Node reference implementation of a device    (phase 0, done)
firmware/           Arduino library                              (phase 1)
web/                TypeScript renderer                          (phase 2)
apps/mobile/        Flutter app                                  (phases 3, 5, done)
docker/             build and run images
```

Everything runs in Docker so the host needs nothing but Docker:

```
# validate protocol vectors
docker run --rm -v "$PWD/protocol":/w -w /w node:22-alpine sh -c "npm install && npm test"
# fake device on ws://localhost:8080/ws
docker build -f docker/fake-device.Dockerfile -t espface-fake . && docker run --rm -p 8080:8080 espface-fake --pin=1234
```
