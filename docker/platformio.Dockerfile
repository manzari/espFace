# PlatformIO with a host toolchain for native unit tests and ESP32 builds. Cache ~/.platformio in a volume.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ make git ca-certificates && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir platformio==6.1.16
ENV PLATFORMIO_CORE_DIR=/pio
WORKDIR /w
ENTRYPOINT ["pio"]
