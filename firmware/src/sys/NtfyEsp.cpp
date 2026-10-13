#ifdef ARDUINO
#include "NtfyEsp.h"
#include <Arduino.h>
#include <HTTPClient.h>
#include "Http.h"

namespace espface {

struct NtfyJob { Notifier* n; Notifier::Msg m; const char* const* ca; };

static void ntfyTask(void* p) {
  NtfyJob* j = (NtfyJob*)p;
  Str url = j->n->server(); url += "/"; url += j->n->topic();
  WiFiClient* cl = makeHttpClient(url.c_str(), j->ca ? *j->ca : nullptr);
  HTTPClient http;
  http.setTimeout(10000);
  if (http.begin(*cl, url)) {
    http.addHeader("Title", j->m.title);
    http.addHeader("Priority", String(j->m.prio));
    if (j->n->token().length()) http.addHeader("Authorization", "Bearer " + j->n->token());
    int code = http.POST(j->m.body);
    if (code != HTTP_CODE_OK) logf("ntfy failed: %d", code);
    http.end();
  }
  delete cl;
  j->n->busy = false;
  delete j;
  vTaskDelete(nullptr);
}

void ntfyInstallSender(Notifier& n, const char* const* ca) {
  n.sender = [&n, ca](const Notifier::Msg& m) {
    NtfyJob* job = new NtfyJob{&n, m, ca};
    if (xTaskCreate(ntfyTask, "ntfy", 10240, job, 1, nullptr) != pdPASS) { delete job; n.busy = false; }
  };
}

}  // namespace espface
#endif
