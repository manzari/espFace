#if defined(ARDUINO) && defined(ESPFACE_BLE)
#include "BleTransport.h"
#include "../core/Core.h"
#include <string>

#define ESPFACE_BLE_SVC  "0000ea00-0000-1000-8000-00805f9b34fb"
#define ESPFACE_BLE_RX   "0000ea01-0000-1000-8000-00805f9b34fb"
#define ESPFACE_BLE_TX   "0000ea02-0000-1000-8000-00805f9b34fb"
#define ESPFACE_BLE_INFO "0000ea03-0000-1000-8000-00805f9b34fb"

namespace espface {

void BleTransport::begin() {
  if (begun_) return;
  begun_ = true;
  if (!name_.length()) name_ = core_->name();
  q_ = xQueueCreate(32, sizeof(Event));
  NimBLEDevice::init(name_.c_str());
  NimBLEDevice::setMTU(ESPFACE_BLE_MTU);
  server_ = NimBLEDevice::createServer();
  server_->setCallbacks(this);
  server_->advertiseOnDisconnect(false);
  NimBLEService* svc = server_->createService(NimBLEUUID(ESPFACE_BLE_SVC));
  NimBLECharacteristic* rx = svc->createCharacteristic(NimBLEUUID(ESPFACE_BLE_RX), NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR, ESPFACE_BLE_MTU);
  rx->setCallbacks(this);
  tx_ = svc->createCharacteristic(NimBLEUUID(ESPFACE_BLE_TX), NIMBLE_PROPERTY::NOTIFY, ESPFACE_BLE_MTU);
  tx_->setCallbacks(this);
  NimBLECharacteristic* info = svc->createCharacteristic(NimBLEUUID(ESPFACE_BLE_INFO), NIMBLE_PROPERTY::READ, 96);
  std::string v(name_.c_str()); v.push_back('\0'); v += core_->id();
  info->setValue((const uint8_t*)v.data(), v.size());
  server_->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(NimBLEUUID(ESPFACE_BLE_SVC));
  adv->setName(name_.c_str());
  adv->enableScanResponse(true);
  advertise();
  core_->addCap("ble");
  logf("ble advertising as %s", name_.c_str());
}

void BleTransport::advertise() {
  if (!server_ || connections() >= ESPFACE_BLE_MAX_CONN) return;
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  if (!adv->isAdvertising()) adv->start();
}

uint8_t BleTransport::connections() const { uint8_t n = 0; for (auto& c : conns_) if (c.slot >= 0) n++; return n; }
BleTransport::Conn* BleTransport::byHandle(uint16_t h) { for (auto& c : conns_) if (c.slot >= 0 && c.handle == h) return &c; return nullptr; }
BleTransport::Conn* BleTransport::bySlot(uint8_t s) { for (auto& c : conns_) if (c.slot == (int8_t)s) return &c; return nullptr; }

// ---- NimBLE host task ---------------------------------------------------------------
void BleTransport::post(EvType t, uint16_t handle, uint8_t* data, size_t len) {
  Event e{t, handle, data, len};
  if (!q_ || xQueueSend(q_, &e, pdMS_TO_TICKS(50)) != pdTRUE) free(data);
}

void BleTransport::onConnect(NimBLEServer*, NimBLEConnInfo& ci) { post(Open, ci.getConnHandle()); }
void BleTransport::onDisconnect(NimBLEServer*, NimBLEConnInfo& ci, int) { post(Close, ci.getConnHandle()); }
void BleTransport::onMTUChange(uint16_t mtu, NimBLEConnInfo& ci) { post(Mtu, ci.getConnHandle(), nullptr, mtu); }
void BleTransport::onSubscribe(NimBLECharacteristic*, NimBLEConnInfo& ci, uint16_t sub) { post(Sub, ci.getConnHandle(), nullptr, sub); }

void BleTransport::onWrite(NimBLECharacteristic* c, NimBLEConnInfo& ci) {
  NimBLEAttValue v = c->getValue();
  if (!v.length()) return;
  uint8_t* buf = (uint8_t*)malloc(v.length());
  if (!buf) return;
  memcpy(buf, v.data(), v.length());
  post(Data, ci.getConnHandle(), buf, v.length());
}

// ---- loop context -----------------------------------------------------------------------
void BleTransport::loop() {
  if (!q_) return;
  Event e;
  while (xQueueReceive(q_, &e, 0) == pdTRUE) {
    Conn* c = byHandle(e.handle);
    switch (e.type) {
      case Open: {
        Conn* fr = nullptr; for (auto& x : conns_) if (x.slot < 0) { fr = &x; break; }
        int slot = fr ? core_->onOpen(this) : -1;
        if (slot < 0) { server_->disconnect(e.handle); break; }
        fr->handle = e.handle; fr->slot = (int8_t)slot; fr->subscribed = false;
        fr->tx.reset(); fr->tx.setMtu(server_->getPeerMTU(e.handle)); fr->rx.reset();
        advertise();
        break;
      }
      case Close:
        if (c) { uint8_t s = (uint8_t)c->slot; c->slot = -1; c->handle = 0xffff; core_->onClose(s); }
        advertise();
        break;
      case Mtu: if (c) c->tx.setMtu((uint16_t)e.len); break;
      case Sub: if (c) c->subscribed = e.len != 0; break;
      case Data:
        if (c) {
          BleReassembler::Result r = c->rx.feed(e.data, e.len);
          if (r == BleReassembler::Message) core_->onMessage((uint8_t)c->slot, c->rx.data(), c->rx.len());
          else if (r == BleReassembler::Oversize) core_->sendErr((uint8_t)c->slot, 2, "message too large");
          else if (r == BleReassembler::Dropped) logf("ble slot %d: chunk gap, message dropped", c->slot);
        }
        free(e.data);
        break;
    }
  }
}

bool BleTransport::sendFrame(uint8_t slot, const char* data, size_t len, bool, bool last) {
  Conn* c = bySlot(slot);
  if (!c || !tx_ || !c->subscribed) return false;
  uint16_t h = c->handle;
  return c->tx.frame(data, len, last, [&](const uint8_t* p, size_t n) {
    for (int i = 0; i < 40; i++) { if (tx_->notify(p, n, h)) return true; vTaskDelay(pdMS_TO_TICKS(5)); }
    return false;
  });
}

void BleTransport::close(uint8_t slot) {
  Conn* c = bySlot(slot);
  if (c && server_) server_->disconnect(c->handle);
}

}  // namespace espface
#endif
