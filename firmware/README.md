# espFace firmware library

Arduino library for ESP32 (core 3.x). The sketch describes widgets; the espFace apps and web renderer draw them.

```cpp
#include <espFace.h>
EspFace face;
void setup() {
  face.begin("Boiler");
  face.setPin("1234");
  face.wifi().autoConnect();
  face.ui().gauge("temp", "Temperature", 0, 120, "°C");
  face.ui().sw("pump", "Pump").onChange([](bool on) { digitalWrite(PUMP, on); });
}
void loop() { face.loop(); face.set("temp", readTemp()); }
```

Development (all in Docker, from the repository root):

```
docker build -f docker/platformio.Dockerfile -t espface-pio .
docker volume create espface-pio
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware espface-pio test -e native        # unit tests
docker run --rm -v "$PWD":/w -v espface-pio:/pio -w /w/firmware --entrypoint sh espface-pio tools/ci-build.sh   # ESP32 builds + footprint.md
```

Compile-time options: `ESPFACE_MAX_CLIENTS` (4), `ESPFACE_LOG_HISTORY` (0), `ESPFACE_RENDERER_HOST`, `ESPFACE_FRAME_SIZE` (1024).
