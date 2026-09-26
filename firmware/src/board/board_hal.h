// The board's side of app::Hal: buttons, touch, LED, backlight, battery,
// sound, the amp and heap figures (plan/DEVICE.md §2–3).
#pragma once
#include "app/device.h"

namespace board {

class BoardHal : public app::Hal {
 public:
  void begin();
  void setFps(uint32_t fps) { fps_ = fps; }
  void setFrameUs(uint32_t draw, uint32_t push) { drawUs_ = draw, pushUs_ = push; }
  // Bluetooth's side, filled in by the main loop.
  void setBle(const char* state, const char* name, const char* id) { bleState_ = state, bleName_ = name, id_ = id; }

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
  uint32_t batteryMv() override;
  bool ampOn() override;
  void say(const voice::Line& l) override;
  void cue(voice::Cue c, uint8_t vol) override;
  void hush() override;
  app::AudioOut audioOut() override;
  bool usbPowered() override { return true; }  // no battery in v1 (DEVICE.md §3)
  const char* deviceId() override { return id_; }
  const char* bleState() override { return bleState_; }
  const char* bleName() override { return bleName_; }
  const char* fwVersion() override { return BOOP_FW_VERSION; }
  const char* gitSha() override { return BOOP_GIT_SHA; }

 private:
  app::TouchCal cal_;         // from NVS; invalid until `boopctl calibrate` has run on this rotation
  app::TouchCal defaultCal_;  // used until then: the raw range, turned by kRotation
  uint32_t fps_ = 0;
  uint32_t drawUs_ = 0, pushUs_ = 0;
  const char* bleState_ = "off";
  const char* bleName_ = "";
  const char* id_ = "b00p-0000";
};

}  // namespace board
