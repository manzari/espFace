#pragma once
#include "../core/Platform.h"
#include "../proto/Writer.h"

namespace espface {

class Core;
class Ui;

// A transport delivers whole messages to the core and sends message frames to a client slot.
class Transport {
 public:
  virtual ~Transport() {}
  virtual const char* name() const = 0;
  virtual void begin() {}
  virtual void loop() {}
  // Send part of one message. first/last mark message boundaries; a transport without fragmentation buffers until last.
  virtual bool sendFrame(uint8_t slot, const char* data, size_t len, bool first, bool last) = 0;
  virtual void close(uint8_t slot) {}
  virtual bool supportsBinary() const { return false; }

  void attach(Core* core) { core_ = core; }
  void use(Ui& ui) { ui_ = &ui; }
  Ui* ui() const { return ui_; }

 protected:
  Core* core_ = nullptr;
  Ui* ui_ = nullptr;
};

// Sink that chunks one message into transport frames.
class FrameSink : public Sink {
 public:
  FrameSink(Transport& t, uint8_t slot) : t_(t), slot_(slot) {}
  void write(const char* data, size_t len) override {
    while (len) {
      size_t take = sizeof buf_ - n_; if (take > len) take = len;
      memcpy(buf_ + n_, data, take); n_ += take; data += take; len -= take;
      if (n_ == sizeof buf_) { t_.sendFrame(slot_, buf_, n_, first_, false); first_ = false; n_ = 0; }
    }
  }
  void end() override { t_.sendFrame(slot_, buf_, n_, first_, true); n_ = 0; first_ = true; }
 private:
  Transport& t_;
  uint8_t slot_;
  char buf_[ESPFACE_FRAME_SIZE];
  size_t n_ = 0;
  bool first_ = true;
};

}  // namespace espface
