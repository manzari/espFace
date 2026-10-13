#pragma once
#include "Transport.h"
#include "BleFramer.h"
#if defined(ARDUINO) && defined(ESPFACE_BLE)
#ifdef ESPFACE_BT_CLASSIC
#error "ESPFACE_BLE (NimBLE) and ESPFACE_BT_CLASSIC (Bluedroid SPP) cannot be combined in one build"
#endif
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

namespace espface {

// GATT server on NimBLE: service ea00, RX ea01 (write / write-no-response), TX ea02 (notify), INFO ea03 (read "name\0id").
// NimBLE callbacks only post to a queue; loop() turns them into core calls. Up to ESPFACE_BLE_MAX_CONN centrals.
class BleTransport : public Transport, public NimBLEServerCallbacks, public NimBLECharacteristicCallbacks {
 public:
  const char* name() const override { return "ble"; }
  void begin() override;
  void loop() override;
  bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) override;
  void close(uint8_t slot) override;
  void setName(const char* n) { name_ = n; }           // advertised name, default: the core name
  bool running() const { return server_ != nullptr; }
  uint8_t connections() const;

  // NimBLE callbacks (host task)
  void onConnect(NimBLEServer* s, NimBLEConnInfo& ci) override;
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& ci, int reason) override;
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& ci) override;
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& ci) override;
  void onSubscribe(NimBLECharacteristic* c, NimBLEConnInfo& ci, uint16_t sub) override;

 private:
  enum EvType : uint8_t { Open, Close, Data, Mtu, Sub };
  struct Event { EvType type; uint16_t handle; uint8_t* data; size_t len; };
  struct Conn { uint16_t handle = 0xffff; int8_t slot = -1; bool subscribed = false; BleChunker tx; BleReassembler rx; };
  void post(EvType t, uint16_t handle, uint8_t* data = nullptr, size_t len = 0);
  Conn* byHandle(uint16_t h);
  Conn* bySlot(uint8_t s);
  void advertise();

  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic* tx_ = nullptr;
  QueueHandle_t q_ = nullptr;
  Conn conns_[ESPFACE_BLE_MAX_CONN];
  Str name_;
  bool begun_ = false;
};

}  // namespace espface
#endif
