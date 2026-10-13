#include "Platform.h"
#include <stdio.h>
#include <stdarg.h>
#include <math.h>

#ifdef ARDUINO
#include <esp_random.h>
#else
#include <chrono>
#include <random>
#endif

namespace espface {

uint32_t nowMs() {
#ifdef ARDUINO
  return millis();
#else
  using namespace std::chrono;
  static const auto t0 = steady_clock::now();
  return (uint32_t)duration_cast<milliseconds>(steady_clock::now() - t0).count();
#endif
}

void randomBytes(uint8_t* out, size_t n) {
#ifdef ARDUINO
  esp_fill_random(out, n);
#else
  static std::random_device rd;
  for (size_t i = 0; i < n; i++) out[i] = (uint8_t)rd();
#endif
}

void toHex(const uint8_t* in, size_t n, char* out) {
  static const char* d = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) { out[2 * i] = d[in[i] >> 4]; out[2 * i + 1] = d[in[i] & 15]; }
  out[2 * n] = 0;
}

static int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool fromHex(const char* hex, uint8_t* out, size_t n) {
  if (!hex || strlen(hex) != 2 * n) return false;
  for (size_t i = 0; i < n; i++) {
    int h = hexVal(hex[2 * i]), l = hexVal(hex[2 * i + 1]);
    if (h < 0 || l < 0) return false;
    out[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

void fmtFloat(float v, char* out, size_t cap) {
  if (isnan(v) || isinf(v)) { snprintf(out, cap, "0"); return; }
  if (v == (float)(int32_t)v && fabsf(v) < 1e9f) { snprintf(out, cap, "%ld", (long)(int32_t)v); return; }
  snprintf(out, cap, "%.4f", (double)v);
  // trim trailing zeros
  char* dot = strchr(out, '.');
  if (!dot) return;
  char* e = out + strlen(out) - 1;
  while (e > dot && *e == '0') *e-- = 0;
  if (e == dot) *e = 0;
}

void logf(const char* fmt, ...) {
  char buf[160];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
#ifdef ARDUINO
  Serial.print("[espFace] "); Serial.println(buf);
#else
  printf("[espFace] %s\n", buf);
#endif
}

}  // namespace espface
