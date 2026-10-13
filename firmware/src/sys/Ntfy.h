#pragma once
#include <functional>
#include <vector>
#include "../core/Platform.h"

namespace espface {

enum class Ntfy : uint8_t { Min = 1, Low = 2, Default = 3, High = 4, Max = 5 };

// Direct ntfy notifications with a rate limit and a small queue; the platform layer supplies the HTTP POST.
class Notifier {
 public:
  struct Msg { Str title, body; uint8_t prio; };
  void configure(const char* server, const char* topic, const char* token);
  bool configured() const { return server_.length() && topic_.length(); }
  void setRateLimit(uint32_t ms) { limitMs_ = ms; }
  uint32_t rateLimit() const { return limitMs_; }
  bool notify(const char* title, const char* msg, Ntfy prio, uint32_t now);   // false when unconfigured or the queue is full
  void loop(uint32_t now);
  size_t queued() const { return q_.size(); }
  uint32_t sent() const { return sent_; }
  const Str& server() const { return server_; }
  const Str& topic() const { return topic_; }
  const Str& token() const { return token_; }
  std::function<void(const Msg&)> sender;   // must clear busy when the request finished
  volatile bool busy = false;

 private:
  enum { QUEUE = 4 };
  Str server_, topic_, token_;
  uint32_t limitMs_ = 10000, lastAt_ = 0, sent_ = 0;
  std::vector<Msg> q_;
};

}  // namespace espface
