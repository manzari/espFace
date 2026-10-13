#pragma once
#include <functional>
#include <vector>
#include "Platform.h"
#include "../ui/Ui.h"
#include "../proto/Session.h"
#include "../transport/Transport.h"
#include "../sys/Store.h"

namespace espface {

enum class RebootReason : uint8_t { Client, Ota, Sketch };

struct ClientInfo {
  uint8_t slot;
  const char* transport;
  bool isWeb;
};

// Platform-independent heart of the library: sessions, message dispatch, UIs.
class Core : public UiHost {
 public:
  Core();
  ~Core();
  void begin(const char* name, Store* store);
  void loop();

  // identity
  Core& setId(const char* id) { id_ = id; return *this; }
  Core& setName(const char* n) { name_ = n; return *this; }
  Core& setProject(const char* p) { proj_ = p; return *this; }
  Core& setIcon(const char* i) { icon_ = i; return *this; }
  Core& setVersion(const char* v) { fw_ = v; return *this; }
  Core& setRepo(const char* r) { repo_ = r; return *this; }
  Core& setAbout(const char* a) { about_ = a; return *this; }
  const char* id() const { return id_.c_str(); }
  const char* name() const { return name_.c_str(); }
  const char* fw() const { return fw_.c_str(); }
  const char* proj() const { return proj_.c_str(); }
  const char* icon() const { return icon_.c_str(); }

  // auth
  void setPin(const char* pin, bool force = false) { auth_.setPin(pin, force); }
  Auth& auth() { return auth_; }

  // uis and transports
  Ui& ui() { return *uis_[0]; }
  Ui& addUi(const char* name);
  Ui* findUi(const char* name);
  void addTransport(Transport* t);
  void addCap(const char* cap);
  bool hasCap(const char* cap) const;

  // transport entry points (called from loop context)
  int onOpen(Transport* t);
  void onClose(uint8_t slot);
  void onMessage(uint8_t slot, const char* data, size_t len);
  void onBinary(uint8_t slot, const uint8_t* data, size_t len);

  // sketch-facing helpers
  void toast(const char* lvl, const char* msg);
  void log(const char* msg, const char* color = nullptr) { ui().logLine(nullptr, msg, color); }
  uint8_t clients() const;
  void onConnect(std::function<void(const ClientInfo&)> fn) { onConnect_ = fn; }
  void onDisconnect(std::function<void(const ClientInfo&)> fn) { onDisconnect_ = fn; }
  void onReboot(std::function<void(RebootReason)> fn) { onReboot_ = fn; }
  void requestReboot(RebootReason r, uint32_t delayMs = 500);
  uint32_t time() const;                      // unix seconds or 0
  int16_t tz() const { return tz_; }
  void setTime(uint32_t unix, bool authoritative = true);
  bool timeValid() const { return timeValid_; }
  uint32_t uptime() const { return nowMs(); }

  // hooks for the platform layer
  std::function<void(JsonWriter&)> infoFill;                                 // chip, heap, ip ... in sys info
  std::function<bool(uint8_t slot, const char* cmd, void* jsonDoc)> sysHook; // wifi.*, ota.*; return true if handled
  std::function<void()> rebootFn;
  std::function<bool(uint8_t slot, const uint8_t* data, size_t len)> binaryHook;

  // UiHost
  void uiBroadcast(Ui& ui, const std::function<void(JsonWriter&)>& fill) override;
  void uiValueChanged(Ui& ui, uint16_t idx) override;
  void uiRebuilt(Ui& ui) override;

  // raw send
  void send(uint8_t slot, const std::function<void(JsonWriter&)>& fill);
  void sendErr(uint8_t slot, int code, const char* msg, const char* ref = nullptr);
  Client* client(uint8_t slot) { return slot < ESPFACE_MAX_CLIENTS ? &clients_[slot] : nullptr; }

 private:
  void handleHello(Client& c, void* doc);
  void handleAuth(Client& c, void* doc);
  void handleTime(Client& c, void* doc);
  void handleSet(Client& c, void* doc);
  void handleEv(Client& c, void* doc);
  void handleDlg(Client& c, void* doc);
  void handlePage(Client& c, void* doc);
  void handleSys(Client& c, void* doc);
  void sendHello(Client& c, bool ok, const char* nonce, uint32_t lock);
  void afterAuth(Client& c);
  void sendFullUpd(Client& c);
  void flush(Client& c);
  Ui& uiFor(Client& c) { return c.ui ? *c.ui : ui(); }

  Str id_, name_, proj_, icon_, fw_, repo_, about_;
  Store* store_ = nullptr;
  Auth auth_;
  std::vector<Ui*> uis_;
  std::vector<Transport*> trs_;
  std::vector<Str> caps_;
  Client clients_[ESPFACE_MAX_CLIENTS];
  std::function<void(const ClientInfo&)> onConnect_, onDisconnect_;
  std::function<void(RebootReason)> onReboot_;
  bool rebootPending_ = false;
  uint32_t rebootAt_ = 0;
  RebootReason rebootReason_ = RebootReason::Sketch;
  bool timeValid_ = false, timeAuthoritative_ = false;
  uint32_t unixAtSync_ = 0, msAtSync_ = 0;
  int16_t tz_ = 0;
};

}  // namespace espface
