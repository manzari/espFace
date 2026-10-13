#pragma once
#include <functional>
#include "../core/Platform.h"
#include "Store.h"

namespace espface {

class Core;

// Seam over Update.h so the OTA state machine runs natively in tests.
class OtaBackend {
 public:
  virtual ~OtaBackend() {}
  virtual bool begin(size_t size, const char* md5) = 0;     // size 0 = unknown
  virtual size_t write(const uint8_t* data, size_t len) = 0;
  virtual bool end() = 0;                                    // verifies the md5
  virtual void abort() = 0;
  virtual const char* error() const { return "update failed"; }
};

// One OTA session at a time: push over WS binary frames, download by URL, or the POST /update fallback.
class Ota {
 public:
  void begin(Core* core, OtaBackend* backend, Store* store = nullptr);
  bool handleSys(uint8_t slot, const char* cmd, void* doc);   // ota.begin, ota.abort, ota.url
  bool onBinary(uint8_t slot, const uint8_t* data, size_t len);
  void onClose(uint8_t slot);
  void loop();
  bool busy() const { return active_; }
  void setTimeout(uint32_t ms) { timeoutMs_ = ms; }
  void setCaCert(const char* pem) { ca_ = pem; }
  const char* caCert() const { return ca_; }

  // session API shared by push, url and http fallback (slot -1 = not bound to a client)
  bool start(int slot, size_t size, const char* md5);
  bool feed(const uint8_t* data, size_t len);
  bool finish();
  void fail(const char* msg);
  void abort();
  std::function<bool(const char* url)> urlFetch;   // platform layer; returns false when it could not start

 private:
  void progress(bool force);
  void done(bool ok, const char* msg);
  Core* core_ = nullptr;
  OtaBackend* be_ = nullptr;
  Store* store_ = nullptr;
  const char* ca_ = nullptr;
  bool active_ = false;
  int slot_ = -1;
  size_t size_ = 0, got_ = 0;
  uint32_t lastPush_ = 0, lastData_ = 0, timeoutMs_ = 30000;
  int lastPct_ = -1;
};

}  // namespace espface
