#pragma once
#include "Transport.h"
#ifdef ARDUINO
#include <esp_http_server.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

namespace espface {

// WebSocket transport on ESP-IDF esp_http_server. Also serves the bootstrap page, captive-portal probes and,
// with ESPFACE_EMBED_WEB, the gzipped renderer at /r/1/app.js and /r/1/app.css.
// Half-dead sockets: a ping every ESPFACE_WS_PING_MS, a client silent for ESPFACE_WS_IDLE_MS is closed.
class WsTransport : public Transport {
 public:
  const char* name() const override { return "ws"; }
  void setPort(uint16_t p) { port_ = p; }
  uint16_t port() const { return port_; }
  void begin() override;
  void loop() override;
  bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) override;
  void close(uint8_t slot) override;
  bool supportsBinary() const override { return true; }
  void setBootstrap(const char* html, size_t len, bool gzip) { html_ = html; htmlLen_ = len; htmlGz_ = gzip; }
  void setRendererHost(const char* host) { host_ = host; }
  httpd_handle_t handle() const { return hd_; }
  bool running() const { return hd_ != nullptr; }

 private:
  enum EvType : uint8_t { Open, Close, Text, Binary, Pong };
  struct Event { EvType type; int fd; uint8_t* data; size_t len; };
  static esp_err_t wsHandler(httpd_req_t* req);
  static esp_err_t pageHandler(httpd_req_t* req);
#ifdef ESPFACE_EMBED_WEB
  static esp_err_t embedHandler(httpd_req_t* req);
#endif
  static void closeFn(httpd_handle_t hd, int fd);
  void post(EvType t, int fd, uint8_t* data = nullptr, size_t len = 0);
  int slotOf(int fd) const;

  httpd_handle_t hd_ = nullptr;
  QueueHandle_t q_ = nullptr;
  SemaphoreHandle_t mx_ = nullptr;
  bool sendRaw(int fd, httpd_ws_type_t type, const char* data, size_t len);
  int fds_[ESPFACE_MAX_CLIENTS];
  uint32_t lastRx_[ESPFACE_MAX_CLIENTS], lastPing_[ESPFACE_MAX_CLIENTS];
  uint16_t port_ = 80;
  const char* html_ = nullptr; size_t htmlLen_ = 0; bool htmlGz_ = false;
  const char* host_ = "";
};

}  // namespace espface
#endif
