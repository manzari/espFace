#ifdef ARDUINO
#include "WsTransport.h"
#include "../core/Core.h"
#include <Arduino.h>
#include <unistd.h>

namespace espface {

void WsTransport::begin() {
  for (auto& f : fds_) f = -1;
  q_ = xQueueCreate(16, sizeof(Event));
  mx_ = xSemaphoreCreateMutex();
  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  cfg.server_port = port_;
  cfg.ctrl_port = 32768 + port_;
  cfg.max_open_sockets = ESPFACE_MAX_CLIENTS + 3;
  cfg.lru_purge_enable = true;
  cfg.close_fn = closeFn;
  cfg.global_user_ctx = this;
  cfg.global_user_ctx_free_fn = [](void*) {};
  cfg.uri_match_fn = httpd_uri_match_wildcard;
  cfg.stack_size = 6144;
  if (httpd_start(&hd_, &cfg) != ESP_OK) {
    logf("port %u busy, trying 8080", port_);
    port_ = 8080; cfg.server_port = 8080; cfg.ctrl_port = 32768 + 8080;
    if (httpd_start(&hd_, &cfg) != ESP_OK) { hd_ = nullptr; logf("http server failed"); return; }
  }
  httpd_uri_t ws = {}; ws.uri = "/ws"; ws.method = HTTP_GET; ws.handler = wsHandler; ws.user_ctx = this; ws.is_websocket = true; ws.handle_ws_control_frames = false;
  httpd_register_uri_handler(hd_, &ws);
  httpd_uri_t page = {}; page.uri = "/*"; page.method = HTTP_GET; page.handler = pageHandler; page.user_ctx = this;
  httpd_register_uri_handler(hd_, &page);
  logf("ws://<ip>:%u/ws ready", port_);
}

void WsTransport::post(EvType t, int fd, uint8_t* data, size_t len) {
  Event e{t, fd, data, len};
  if (xQueueSend(q_, &e, pdMS_TO_TICKS(50)) != pdTRUE && data) free(data);
}

int WsTransport::slotOf(int fd) const { for (int i = 0; i < ESPFACE_MAX_CLIENTS; i++) if (fds_[i] == fd) return i; return -1; }

esp_err_t WsTransport::wsHandler(httpd_req_t* req) {
  WsTransport* self = (WsTransport*)req->user_ctx;
  int fd = httpd_req_to_sockfd(req);
  if (req->method == HTTP_GET) { self->post(Open, fd); return ESP_OK; }
  httpd_ws_frame_t f = {};
  if (httpd_ws_recv_frame(req, &f, 0) != ESP_OK) return ESP_FAIL;
  if (f.type != HTTPD_WS_TYPE_TEXT && f.type != HTTPD_WS_TYPE_BINARY) return ESP_OK;
  size_t cap = f.type == HTTPD_WS_TYPE_TEXT ? 2048 : 4096;
  if (f.len > cap) { logf("frame too large (%u)", (unsigned)f.len); return ESP_OK; }
  uint8_t* buf = (uint8_t*)malloc(f.len + 1);
  if (!buf) return ESP_ERR_NO_MEM;
  f.payload = buf;
  if (httpd_ws_recv_frame(req, &f, f.len) != ESP_OK) { free(buf); return ESP_FAIL; }
  buf[f.len] = 0;
  self->post(f.type == HTTPD_WS_TYPE_TEXT ? Text : Binary, fd, buf, f.len);
  return ESP_OK;
}

void WsTransport::closeFn(httpd_handle_t hd, int fd) {
  WsTransport* self = (WsTransport*)httpd_get_global_user_ctx(hd);
  if (self) self->post(Close, fd);
  ::close(fd);
}

esp_err_t WsTransport::pageHandler(httpd_req_t* req) {
  WsTransport* self = (WsTransport*)req->user_ctx;
  httpd_resp_set_type(req, "text/html; charset=utf-8");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  if (self->htmlGz_) httpd_resp_set_hdr(req, "Content-Encoding", "gzip");
  if (!self->html_) return httpd_resp_sendstr(req, "espFace device");
  return httpd_resp_send(req, self->html_, self->htmlLen_);
}

void WsTransport::loop() {
  if (!q_) return;
  Event e;
  while (xQueueReceive(q_, &e, 0) == pdTRUE) {
    switch (e.type) {
      case Open: {
        int slot = core_->onOpen(this);
        if (slot < 0) { httpd_sess_trigger_close(hd_, e.fd); break; }
        fds_[slot] = e.fd;
        break;
      }
      case Close: {
        int slot = slotOf(e.fd);
        if (slot >= 0) { fds_[slot] = -1; core_->onClose((uint8_t)slot); }
        break;
      }
      case Text: case Binary: {
        int slot = slotOf(e.fd);
        if (slot >= 0) {
          if (e.type == Text) core_->onMessage((uint8_t)slot, (const char*)e.data, e.len);
          else core_->onBinary((uint8_t)slot, e.data, e.len);
        }
        free(e.data);
        break;
      }
    }
  }
}

bool WsTransport::sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) {
  if (!hd_ || slot >= ESPFACE_MAX_CLIENTS || fds_[slot] < 0) return false;
  httpd_ws_frame_t f = {};
  f.type = first ? HTTPD_WS_TYPE_TEXT : HTTPD_WS_TYPE_CONTINUE;
  f.final = last;
  f.fragmented = !(first && last);
  f.payload = (uint8_t*)data;
  f.len = len;
  xSemaphoreTake(mx_, portMAX_DELAY);
  esp_err_t r = httpd_ws_send_frame_async(hd_, fds_[slot], &f);
  xSemaphoreGive(mx_);
  return r == ESP_OK;
}

void WsTransport::close(uint8_t slot) {
  if (hd_ && slot < ESPFACE_MAX_CLIENTS && fds_[slot] >= 0) httpd_sess_trigger_close(hd_, fds_[slot]);
}

}  // namespace espface
#endif
