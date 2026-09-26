#include "board/board_hal.h"

#include <Arduino.h>
#include <Preferences.h>
#include <esp_heap_caps.h>

#include "board/audio.h"
#include "board/display.h"
#include "board/pins.h"

namespace board {

namespace {
constexpr uint32_t kLedHz = 5000;
constexpr uint8_t kLedBits = 8;
constexpr const char* kNvsSpace = "boop";
// The touch calibration with the screen it was fitted on (app::SavedTouchCal).
// "touchcal" held the portrait build's bare map; it's deleted, never read.
constexpr const char* kNvsTouchCal = "touchcal2";
constexpr const char* kNvsTouchCalPortrait = "touchcal";

void ledChannel(int pin, uint8_t level) { ledcWrite(pin, 255 - level); }  // common anode
}  // namespace

void BoardHal::begin() {
  pinMode(pins::kAmpEnable, OUTPUT);
  digitalWrite(pins::kAmpEnable, HIGH);  // amp off by default (active low)
  pinMode(pins::kMainButton, INPUT_PULLUP);
  pinMode(pins::kTouchIrq, INPUT);
  for (int pin : {pins::kLedRed, pins::kLedGreen, pins::kLedBlue}) {
    ledcAttach(pin, kLedHz, kLedBits);
    ledChannel(pin, 0);
  }
  defaultCal_ = app::defaultTouchCal(kRotation);
  Preferences nvs;
  if (nvs.begin(kNvsSpace, false)) {
    if (nvs.isKey(kNvsTouchCalPortrait)) nvs.remove(kNvsTouchCalPortrait);
    app::SavedTouchCal saved;
    size_t n = nvs.isKey(kNvsTouchCal) ? nvs.getBytes(kNvsTouchCal, &saved, sizeof(saved)) : 0;
    app::TouchCal c;
    if (app::loadTouchCal(&saved, n, kRotation, c)) cal_ = c;
    nvs.end();
  }
}

uint32_t BoardHal::realMs() { return millis(); }

bool BoardHal::bootDown() { return digitalRead(pins::kMainButton) == LOW; }

bool BoardHal::touch(int& x, int& y) {
  int rx, ry, rz;
  bool irq;
  board::touchRaw(rx, ry, rz, irq);
  if (!irq || rz <= 0) return false;
  (cal_.valid ? cal_ : defaultCal_).map(rx, ry, x, y);
  return true;
}

void BoardHal::touchRaw(int& x, int& y, int& z, bool& irq) { board::touchRaw(x, y, z, irq); }

void BoardHal::setTouchCal(const app::TouchCal& c) {
  cal_ = c;
  Preferences nvs;
  if (!nvs.begin(kNvsSpace, false)) return;
  if (c.valid) {
    app::SavedTouchCal saved = app::saveTouchCal(c, kRotation);
    nvs.putBytes(kNvsTouchCal, &saved, sizeof(saved));
  } else {
    nvs.remove(kNvsTouchCal);
  }
  nvs.end();
}

void BoardHal::setLed(uint32_t rgb) {
  ledChannel(pins::kLedRed, (rgb >> 16) & 0xFF);
  ledChannel(pins::kLedGreen, (rgb >> 8) & 0xFF);
  ledChannel(pins::kLedBlue, rgb & 0xFF);
}

void BoardHal::setBacklight(uint8_t level) { displayBacklight(level); }

uint32_t BoardHal::heapFree() { return heap_caps_get_free_size(MALLOC_CAP_8BIT); }

uint32_t BoardHal::heapMin() { return heap_caps_get_minimum_free_size(MALLOC_CAP_8BIT); }

uint32_t BoardHal::batteryMv() {
  if (!pins::kHasBattery) return 0;
  return analogReadMilliVolts(pins::kBattery) * 2;  // 2:1 divider, assumed
}

bool BoardHal::ampOn() { return digitalRead(pins::kAmpEnable) == LOW; }

void BoardHal::say(const voice::Line& l) { audioSay(l); }
void BoardHal::cue(voice::Cue c, uint8_t vol) { audioCue(c, vol); }
void BoardHal::hush() { audioHush(); }
app::AudioOut BoardHal::audioOut() { return board::audioOut(); }

}  // namespace board
