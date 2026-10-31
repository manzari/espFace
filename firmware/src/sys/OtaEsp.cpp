#ifdef ARDUINO
#include "OtaEsp.h"
#include <Arduino.h>
#include <Update.h>
#include <HTTPClient.h>
#include <vector>
#include "Http.h"
#include "../core/Core.h"

namespace espface {

bool UpdateBackend::begin(size_t size, const char* md5) {
  if (!Update.begin(size ? size : UPDATE_SIZE_UNKNOWN, U_FLASH)) return false;
  if (md5 && !Update.setMD5(md5)) { Update.abort(); return false; }
  return true;
}
size_t UpdateBackend::write(const uint8_t* data, size_t len) { return Update.write((uint8_t*)data, len); }
bool UpdateBackend::end() { return Update.end(true); }
void UpdateBackend::abort() { Update.abort(); }
const char* UpdateBackend::error() const { return Update.errorString(); }

// ---- ota.url --------------------------------------------------------------------
static bool fetchUrl(Ota& ota, const char* url) {
  WiFiClient* cl = makeHttpClient(url, ota.caCert());
  HTTPClient http;
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  http.setTimeout(15000);
  http.setReuse(false);
  if (!http.begin(*cl, url)) { delete cl; ota.fail("bad url"); return false; }
  int code = http.GET();
  if (code != HTTP_CODE_OK) {
    char m[40]; snprintf(m, sizeof m, "http %d", code);
    http.end(); delete cl; ota.fail(m); return false;
  }
  int len = http.getSize();
  if (!ota.start(-1, len > 0 ? (size_t)len : 0, nullptr)) { http.end(); delete cl; ota.fail(Update.errorString()); return false; }
  WiFiClient* s = http.getStreamPtr();
  uint8_t buf[1024];
  long remaining = len;
  uint32_t idle = millis();
  while (ota.busy() && http.connected() && (len < 0 || remaining > 0)) {
    size_t n = s->available();
    if (!n) {
      if (millis() - idle > 15000) { ota.fail("timeout"); break; }
      delay(1); continue;
    }
    if (n > sizeof buf) n = sizeof buf;
    n = s->read(buf, n);
    if (!ota.feed(buf, n)) break;
    remaining -= (long)n; idle = millis();
  }
  if (ota.busy()) ota.finish();   // size reached, or the server closed a chunked stream
  http.end(); delete cl;
  return true;
}

void otaInstallUrlFetch(Ota& ota) { ota.urlFetch = [&ota](const char* url) { return fetchUrl(ota, url); }; }

// ---- POST /update ----------------------------------------------------------------
struct HttpCtx { Ota* ota; Core* core; };

static bool authorized(httpd_req_t* req, Core& core) {
  if (!core.auth().hasPin()) return true;
  char tok[48] = "";
  char hdr[64];
  if (httpd_req_get_hdr_value_str(req, "Authorization", hdr, sizeof hdr) == ESP_OK && !strncmp(hdr, "Bearer ", 7)) strncpy(tok, hdr + 7, sizeof tok - 1);
  else {
    char q[96];
    if (httpd_req_get_url_query_str(req, q, sizeof q) == ESP_OK) httpd_query_key_value(q, "tok", tok, sizeof tok);
  }
  return tok[0] && core.auth().validToken(tok);
}

// Streams a multipart body: drops the part headers, stops at the closing boundary.
struct MultipartBody {
  Str term;                 // "\r\n--" + boundary
  std::vector<uint8_t> pend;
  bool inBody = false, finished = false;
  bool push(Ota& ota, const uint8_t* d, size_t n) {
    if (finished) return true;
    pend.insert(pend.end(), d, d + n);
    if (!inBody) {
      for (size_t i = 0; i + 3 < pend.size(); i++) if (!memcmp(&pend[i], "\r\n\r\n", 4)) { pend.erase(pend.begin(), pend.begin() + i + 4); inBody = true; break; }
      if (!inBody) { if (pend.size() > 4096) return false; return true; }
    }
    size_t tl = term.length();
    for (size_t i = 0; i + tl <= pend.size(); i++) if (!memcmp(&pend[i], term.c_str(), tl)) {
      finished = true;
      bool ok = i == 0 || ota.feed(&pend[0], i);
      pend.clear();
      return ok;
    }
    if (pend.size() > tl) {
      size_t emit = pend.size() - tl;
      if (!ota.feed(&pend[0], emit)) return false;
      pend.erase(pend.begin(), pend.begin() + emit);
    }
    return true;
  }
};

static esp_err_t updateHandler(httpd_req_t* req) {
  HttpCtx* ctx = (HttpCtx*)req->user_ctx;
  httpd_resp_set_type(req, "text/plain");
  if (!ctx->core->hasCap("ota")) { httpd_resp_set_status(req, "404 Not Found"); return httpd_resp_sendstr(req, "ota disabled"); }
  if (!authorized(req, *ctx->core)) { httpd_resp_set_status(req, "401 Unauthorized"); return httpd_resp_sendstr(req, "unauthorized"); }
  if (ctx->ota->busy()) { httpd_resp_set_status(req, "409 Conflict"); return httpd_resp_sendstr(req, "ota in progress"); }
  char ctype[160] = "";
  httpd_req_get_hdr_value_str(req, "Content-Type", ctype, sizeof ctype);
  MultipartBody mp;
  bool multipart = !strncmp(ctype, "multipart/form-data", 19);
  if (multipart) {
    const char* b = strstr(ctype, "boundary=");
    if (!b) { httpd_resp_set_status(req, "400 Bad Request"); return httpd_resp_sendstr(req, "no boundary"); }
    b += 9; if (*b == '"') b++;
    mp.term = "\r\n--"; while (*b && *b != '"' && *b != ';') mp.term += *b++;
  }
  size_t total = req->content_len;
  if (!total || !ctx->ota->start(-1, multipart ? 0 : total, nullptr)) { httpd_resp_set_status(req, "500 Internal Server Error"); return httpd_resp_sendstr(req, Update.errorString()); }
  uint8_t buf[1024];
  size_t remaining = total;
  bool ok = true;
  while (remaining && ok) {
    int n = httpd_req_recv(req, (char*)buf, remaining < sizeof buf ? remaining : sizeof buf);
    if (n <= 0) { if (n == HTTPD_SOCK_ERR_TIMEOUT) continue; ok = false; break; }
    remaining -= (size_t)n;
    ok = multipart ? mp.push(*ctx->ota, buf, (size_t)n) : ctx->ota->feed(buf, (size_t)n);
  }
  if (ok && ctx->ota->busy()) ok = ctx->ota->finish();
  else if (ctx->ota->busy()) ctx->ota->fail("upload failed");
  if (!ok) { httpd_resp_set_status(req, "500 Internal Server Error"); return httpd_resp_sendstr(req, "update failed"); }
  return httpd_resp_sendstr(req, "OK, rebooting");
}

void otaRegisterHttp(Ota& ota, Core& core, httpd_handle_t hd) {
  if (!hd) return;
  static HttpCtx ctx;
  ctx.ota = &ota; ctx.core = &core;
  httpd_uri_t u = {}; u.uri = "/update"; u.method = HTTP_POST; u.handler = updateHandler; u.user_ctx = &ctx;
  httpd_register_uri_handler(hd, &u);
}

}  // namespace espface
#endif
