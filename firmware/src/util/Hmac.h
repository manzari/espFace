#pragma once
#include <stdint.h>
#include <stddef.h>

namespace espface {

// Portable SHA-256 and HMAC-SHA256 (used for PIN proof on every platform).
void sha256(const uint8_t* data, size_t len, uint8_t out[32]);
void hmacSha256(const uint8_t* key, size_t keyLen, const uint8_t* msg, size_t msgLen, uint8_t out[32]);
// mac for the espFace PIN proof: HMAC(key = pin, msg = nonceHex + deviceId), as lowercase hex (65 bytes incl. NUL).
void pinMac(const char* pin, const char* nonceHex, const char* deviceId, char outHex[65]);
bool constantTimeEq(const char* a, const char* b, size_t n);

}  // namespace espface
