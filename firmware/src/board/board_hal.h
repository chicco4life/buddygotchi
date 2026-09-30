// The board's side of app::Hal: buttons, touch, LED, backlight, sound, the
// amp, heap figures and Bluetooth's state (plan/DEVICE.md §2–3). The sound
// and the card's methods are in board/audio.cpp and board/card.cpp.
#pragma once
#include "app/device.h"

namespace links {
class Ble;
}

namespace board {

class BoardHal : public app::Hal {
 public:
  void begin();
  // Bluetooth, once it has started (or failed to): its state, name and the
  // device ID it took from the MAC.
  void setBle(const links::Ble* ble) { ble_ = ble; }

  uint32_t realMs() override;
  bool bootDown() override;
  bool touch(int& x, int& y) override;
  void touchRaw(int& x, int& y, int& z, bool& irq) override;
  void setTouchCal(const app::TouchCal& c) override;
  app::TouchCal touchCal() override { return cal_; }
  void setLed(uint32_t rgb) override;
  void setBacklight(uint8_t level) override;
  uint32_t heapFree() override;
  uint32_t heapMin() override;
  bool ampOn() override;
  void say(const voice::Line& l) override;
  void hush() override;
  void effect(const voice::Effect& e) override;
  void stopEffects() override;
  app::AudioOut audioOut() override;
  const char* deviceId() override;
  const char* bleState() override;
  const char* bleName() override;
  const char* cardState() override;
  bool packBegin(bool keep, uint32_t& have, const char*& why) override;
  bool packAppend(const uint8_t* d, size_t n, uint32_t& have) override;
  bool packEnd(uint32_t size, uint32_t crc, const char*& why) override;
  const char* fwVersion() override;
  const char* gitSha() override;

 private:
  app::TouchCal cal_;         // from NVS; invalid until `boopctl calibrate` has run on this rotation
  app::TouchCal defaultCal_;  // used until then: the raw range, turned by kRotation
  const links::Ble* ble_ = nullptr;
};

}  // namespace board
