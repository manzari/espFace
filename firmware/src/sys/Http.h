#pragma once
#include "../core/Platform.h"
#ifdef ARDUINO
#include <WiFiClient.h>
#ifndef ESPFACE_NO_TLS
#include <WiFiClientSecure.h>
#endif

namespace espface {

// Plain or TLS client for a URL. Without a CA certificate https is used unverified (setInsecure).
// -DESPFACE_NO_TLS drops the TLS client (~170 KB flash); https URLs then fail with a log line.
inline WiFiClient* makeHttpClient(const char* url, const char* ca) {
  if (strncmp(url, "https://", 8) == 0) {
#ifdef ESPFACE_NO_TLS
    logf("https not available (ESPFACE_NO_TLS)");
#else
    WiFiClientSecure* s = new WiFiClientSecure();
    if (ca) s->setCACert(ca); else s->setInsecure();
    return s;
#endif
  }
  return new WiFiClient();
}

}  // namespace espface
#endif
