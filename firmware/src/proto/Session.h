#pragma once
#include "../core/Platform.h"
#include "../sys/Store.h"

namespace espface {

class Transport;
class Ui;

struct Client {
  bool used = false;
  bool authed = false;
  bool ready = false;           // ui and upd delivered, onConnect fired
  bool helloSeen = false;
  bool isWeb = false;
  uint8_t slot = 0;
  Transport* tr = nullptr;
  Ui* ui = nullptr;
  int8_t page = -1;             // index of the page widget the client views, -1 = first
  bool hasNonce = false;
  char nonce[33] = {0};
  uint32_t lastFlush = 0;
  uint32_t connectedAt = 0;

  void reset() { *this = Client(); }
};

// PIN, lockout and session tokens. Tokens live in the store as t0..t7.
class Auth {
 public:
  enum { MaxTokens = 8, LockAfter = 5, LockSeconds = 60 };
  void begin(Store* store);
  void setPin(const char* pin, bool force = false);   // sketch-level; a PIN set at runtime wins unless force
  bool setPinRuntime(const char* pin);                  // from sys pin.set; clears tokens
  bool hasPin() const { return pin_.length() > 0; }
  const Str& pin() const { return pin_; }
  bool validToken(const char* tok);
  Str issueToken();
  void revoke();
  uint32_t lockLeft(uint32_t now) const;
  // returns true on success; on failure updates counters. left/lock report the state.
  bool check(const char* mac, const char* nonce, const char* deviceId, const char* pinOverride, uint32_t now, uint8_t& left, uint32_t& lock);
  void makeNonce(char out[33]);

 private:
  void loadTokens();
  Store* store_ = nullptr;
  Str pin_;
  uint8_t failed_ = 0;
  uint32_t lockUntil_ = 0;
  Str tokens_[MaxTokens];
  uint8_t ntok_ = 0;
};

}  // namespace espface
