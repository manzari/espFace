#pragma once
#include "Ota.h"
#ifdef ARDUINO
#include <esp_http_server.h>

namespace espface {

class Core;

// Update.h behind the OtaBackend seam.
class UpdateBackend : public OtaBackend {
 public:
  bool begin(size_t size, const char* md5) override;
  size_t write(const uint8_t* data, size_t len) override;
  bool end() override;
  void abort() override;
  const char* error() const override;
};

// ota.url: blocking download with HTTPClient (follows redirects), progress pushes between chunks.
void otaInstallUrlFetch(Ota& ota);
// POST /update (raw body or multipart/form-data); needs ?tok=<session token> or Authorization: Bearer when a PIN is set.
void otaRegisterHttp(Ota& ota, Core& core, httpd_handle_t hd);

}  // namespace espface
#endif
