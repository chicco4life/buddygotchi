// The board's side of app::Hal: buttons, touch, LED, backlight, sound, the
// amp, heap figures and Bluetooth's state (plan/DEVICE.md §2–3).
#pragma once
#include "app/device.h"

namespace links {
class Ble;
}

namespace board {

class BoardHal : public app::Hal {
 public:
  void begin();
  void setFps(uint32_t fps) { fps_ = fps; }
  void setFrameUs(uint32_t draw, uint32_t push) { drawUs_ = draw, pushUs_ = push; }
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
  uint32_t fps() override { return fps_; }
  void frameUs(uint32_t& draw, uint32_t& push) override { draw = drawUs_, push = pushUs_; }
  bool ampOn() override;
  void say(const voice::Line& l) override;
  void cue(voice::Cue c, uint8_t vol) override;
  void hush() override;
  app::AudioOut audioOut() override;
  const char* deviceId() override;
  const char* bleState() override;
  const char* bleName() override;
  const char* fwVersion() override;
  const char* gitSha() override;

 private:
  app::TouchCal cal_;         // from NVS; invalid until `boopctl calibrate` has run on this rotation
  app::TouchCal defaultCal_;  // used until then: the raw range, turned by kRotation
  uint32_t fps_ = 0;
  uint32_t drawUs_ = 0, pushUs_ = 0;
  const links::Ble* ble_ = nullptr;
};

}  // namespace board
