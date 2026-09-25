// The board's side of app::Hal: buttons, touch, LED, backlight, battery,
// the amp and heap figures (plan/DEVICE.md §2–3).
#pragma once
#include "app/device.h"

namespace board {

class BoardHal : public app::Hal {
 public:
  void begin();
  void setFps(uint32_t fps) { fps_ = fps; }

  uint32_t realMs() override;
  bool bootDown() override;
  bool touch(int& x, int& y) override;
  void touchRaw(int& x, int& y, int& z, bool& irq) override;
  void setLed(uint32_t rgb) override;
  void setBacklight(uint8_t level) override;
  uint32_t heapFree() override;
  uint32_t heapMin() override;
  uint32_t fps() override { return fps_; }
  uint32_t batteryMv() override;
  bool ampOn() override;
  const char* fwVersion() override { return BOOP_FW_VERSION; }
  const char* gitSha() override { return BOOP_GIT_SHA; }

 private:
  uint32_t fps_ = 0;
};

}  // namespace board
