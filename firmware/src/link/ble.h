// Bluetooth: a NimBLE Nordic UART peripheral named Boop-XXXX, with no
// security in v1 (plan/PROTOCOL.md §2, plan/DEVICE.md §4). Received bytes
// cross from the Bluetooth task to the main loop through a ring, and the
// main loop does everything else, so the device core stays single-threaded.
// A link the Mac has gone quiet on is dropped (Device::shouldDrop), so a
// killed app's leftover link can't stop the device advertising.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/device.h"
#include "app/line_reader.h"
#include "app/packets.h"

namespace links {

class Ble : public app::Out {
 public:
  Ble();

  // Releases Classic Bluetooth's memory and starts advertising. Call after
  // the canvas is allocated.
  bool begin();
  // From the main loop: connection changes and one whole received line go
  // to the device core. Returns true if it handled a line.
  bool poll(app::Device& device);

  // Replies and device → Mac messages, sent as notifications.
  void write(const char* s, size_t n) override;

  const char* state() const;          // "off", "idle", "adv" or "conn"
  const char* name() const { return name_; }  // Boop-XXXX
  const char* id() const { return id_; }      // b00p-xxxx

 private:
  static void sendPacket(void* ctx, const uint8_t* data, size_t n);

  char name_[12] = "";  // both from the MAC, in begin()
  char id_[12] = "";
  bool started_ = false;
  bool connected_ = false;  // as the main loop last saw it
  uint32_t advCheckedAt_ = 0;
  app::LineReader line_;
  app::PacketWriter out_;
};

}  // namespace links
