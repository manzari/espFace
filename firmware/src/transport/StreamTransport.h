#pragma once
#include "Transport.h"
#include "LineFramer.h"
#ifdef ARDUINO
#include <Stream.h>
namespace espface { using StreamIo = ::Stream; }
#else
namespace espface {
// Native stand-in for Arduino Stream (tests).
struct StreamIo {
  virtual ~StreamIo() {}
  virtual int available() = 0;
  virtual int read() = 0;
  virtual size_t write(const uint8_t* data, size_t len) = 0;
};
}
#endif

namespace espface {

// One client over any byte stream (UART, USB CDC, BluetoothSerial): one JSON message per '\n' line.
// The slot opens on the first valid line (or on begin() with setOpenOnBegin), closes on close(), idle timeout
// or endSession(); a new hello line restarts the session.
class StreamTransport : public Transport {
 public:
  explicit StreamTransport(StreamIo& io, const char* name = "stream") : io_(io), name_(name) {}
  const char* name() const override { return name_; }
  void begin() override;
  void loop() override;
  bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) override;
  void close(uint8_t slot) override;
  void setIdleTimeout(uint32_t ms) { idleMs_ = ms; }   // 0 = never (default)
  void setOpenOnBegin(bool on) { openOnBegin_ = on; }
  bool open() const { return slot_ >= 0; }
  int slot() const { return slot_; }
  void endSession();                                   // closes the client slot, keeps the stream

 protected:
  StreamIo& io_;

 private:
  bool openSlot();
  void rawErr(int code, const char* msg);
  const char* name_;
  LineFramer lf_;
  int slot_ = -1;
  uint32_t idleMs_ = 0, lastRx_ = 0;
  bool openOnBegin_ = false, closePending_ = false, begun_ = false;
};

}  // namespace espface
