#include "Ntfy.h"

namespace espface {

void Notifier::configure(const char* server, const char* topic, const char* token) {
  char buf[160]; strncpy(buf, server ? server : "", sizeof buf - 1); buf[sizeof buf - 1] = 0;
  size_t n = strlen(buf); while (n && buf[n - 1] == '/') buf[--n] = 0;
  server_ = buf; topic_ = topic ? topic : ""; token_ = token ? token : "";
}

bool Notifier::notify(const char* title, const char* msg, Ntfy prio, uint32_t now) {
  if (!configured() || q_.size() >= QUEUE) return false;
  Msg m; m.title = title ? title : ""; m.body = msg ? msg : ""; m.prio = (uint8_t)prio;
  q_.push_back(m);
  loop(now);
  return true;
}

void Notifier::loop(uint32_t now) {
  if (q_.empty() || busy || !sender) return;
  if (sent_ && (uint32_t)(now - lastAt_) < limitMs_) return;
  Msg m = q_.front(); q_.erase(q_.begin());
  lastAt_ = now; sent_++; busy = true;
  sender(m);
}

}  // namespace espface
