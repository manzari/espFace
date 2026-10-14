#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#ifdef ARDUINO
#include <Arduino.h>
namespace espface { using Str = String; }
#else
#include <string>
namespace espface { using Str = std::string; }
#endif

#ifndef ESPFACE_MAX_CLIENTS
#define ESPFACE_MAX_CLIENTS 4
#endif
#ifndef ESPFACE_LOG_HISTORY
#define ESPFACE_LOG_HISTORY 0
#endif
#ifndef ESPFACE_FLUSH_MS
#define ESPFACE_FLUSH_MS 100
#endif
#ifndef ESPFACE_FRAME_SIZE
#define ESPFACE_FRAME_SIZE 1024
#endif
#ifndef ESPFACE_MAX_MSG
#define ESPFACE_MAX_MSG 2048
#endif
#ifndef ESPFACE_AUTH_TIMEOUT_MS
#define ESPFACE_AUTH_TIMEOUT_MS 30000   // a session that never authenticates is closed after this
#endif
#ifndef ESPFACE_WS_PING_MS
#define ESPFACE_WS_PING_MS 20000        // WebSocket ping interval
#endif
#ifndef ESPFACE_WS_IDLE_MS
#define ESPFACE_WS_IDLE_MS 60000        // WebSocket client closed after this long without a frame (incl. pong)
#endif
#ifndef ESPFACE_WS_SOCKET_TIMEOUT_S
#define ESPFACE_WS_SOCKET_TIMEOUT_S 10  // esp_http_server recv/send wait timeout
#endif
#ifndef ESPFACE_BLE_MTU
#define ESPFACE_BLE_MTU 512
#endif
#ifndef ESPFACE_BLE_MAX_CONN
#define ESPFACE_BLE_MAX_CONN 2
#endif
#define ESPFACE_PROTO_VERSION 1
#define ESPFACE_LIB_VERSION "1.0.0"

namespace espface {

uint32_t nowMs();
void randomBytes(uint8_t* out, size_t n);
void toHex(const uint8_t* in, size_t n, char* out);  // lowercase, NUL terminated, out needs 2n+1
bool fromHex(const char* hex, uint8_t* out, size_t n);
void fmtFloat(float v, char* out, size_t cap);          // shortest reasonable representation
inline bool strEq(const Str& a, const char* b) { return strcmp(a.c_str(), b) == 0; }
void logf(const char* fmt, ...);
#ifdef ARDUINO
void setLogOutput(Print* p);   // default &Serial, nullptr silences logf
#endif

}  // namespace espface
