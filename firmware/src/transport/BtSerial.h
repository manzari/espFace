#pragma once
#include "StreamTransport.h"
#if defined(ARDUINO) && defined(ESPFACE_BT_CLASSIC)
#ifdef ESPFACE_BLE
#error "ESPFACE_BT_CLASSIC (Bluedroid SPP) and ESPFACE_BLE (NimBLE) cannot be combined in one build"
#endif
#if !CONFIG_IDF_TARGET_ESP32
#error "ESPFACE_BT_CLASSIC needs a classic ESP32; S2/S3/C3/C6 have no Bluetooth Classic radio"
#endif
#include <BluetoothSerial.h>

namespace espface {

// Bluetooth Classic SPP: a StreamTransport over BluetoothSerial. The slot follows the SPP link.
class BtSerialTransport : public StreamTransport {
 public:
  BtSerialTransport() : StreamTransport(bt_, "bt") {}
  void setName(const char* n) { name_ = n; }   // Bluetooth name, default: the core name
  void begin() override;
  void loop() override;
  BluetoothSerial& serial() { return bt_; }

 private:
  BluetoothSerial bt_;
  Str name_;
  bool started_ = false, hadClient_ = false;
};

}  // namespace espface
#endif
