// Footprint baseline: the system libraries any comparable sketch already pays for, without espFace.
#include <WiFi.h>
#include <ESPmDNS.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <esp_http_server.h>

DNSServer dns;
Preferences prefs;
httpd_handle_t hd;

static esp_err_t h(httpd_req_t* r) { return httpd_resp_sendstr(r, "ok"); }

void setup() {
  Serial.begin(115200);
  prefs.begin("base", false);
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP("baseline");
  WiFi.begin(prefs.getString("ssid", "x").c_str(), "y");
  dns.start(53, "*", WiFi.softAPIP());
  MDNS.begin("baseline"); MDNS.addService("http", "tcp", 80);
  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  httpd_start(&hd, &cfg);
  httpd_uri_t u = {}; u.uri = "/"; u.method = HTTP_GET; u.handler = h; u.is_websocket = true;
  httpd_register_uri_handler(hd, &u);
}

void loop() { dns.processNextRequest(); delay(10); }
