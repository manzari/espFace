#pragma once
#include "Ntfy.h"
#ifdef ARDUINO

namespace espface {

// Installs the HTTP POST sender: one FreeRTOS task per message, so loop() never blocks on the network.
// *ca points to an optional CA certificate for https (nullptr = unverified).
void ntfyInstallSender(Notifier& n, const char* const* ca);

}  // namespace espface
#endif
