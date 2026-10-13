#if defined(ARDUINO) && defined(ESPFACE_BT_CLASSIC)
#include "BtSerial.h"
#include "../core/Core.h"

namespace espface {

void BtSerialTransport::begin() {
  if (!started_) {
    started_ = true;
    if (!name_.length()) name_ = core_->name();
    if (bt_.begin(name_)) { core_->addCap("bt"); logf("bluetooth classic spp as %s", name_.c_str()); }
    else logf("bluetooth classic failed");
  }
  StreamTransport::begin();
}

void BtSerialTransport::loop() {
  bool has = bt_.hasClient();
  if (hadClient_ && !has) endSession();
  hadClient_ = has;
  StreamTransport::loop();
}

}  // namespace espface
#endif
