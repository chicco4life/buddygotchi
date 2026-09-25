#include "board/board_hal.h"

#include <Arduino.h>
#include <esp_heap_caps.h>

#include "board/audio.h"
#include "board/display.h"
#include "board/pins.h"

namespace board {

namespace {
constexpr uint32_t kLedHz = 5000;
constexpr uint8_t kLedBits = 8;

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
}

uint32_t BoardHal::realMs() { return millis(); }

bool BoardHal::bootDown() { return digitalRead(pins::kMainButton) == LOW; }

bool BoardHal::touch(int& x, int& y) { return touchRead(x, y); }

void BoardHal::touchRaw(int& x, int& y, int& z, bool& irq) { board::touchRaw(x, y, z, irq); }

void BoardHal::setLed(uint32_t rgb) {
  ledChannel(pins::kLedRed, (rgb >> 16) & 0xFF);
  ledChannel(pins::kLedGreen, (rgb >> 8) & 0xFF);
  ledChannel(pins::kLedBlue, rgb & 0xFF);
}

void BoardHal::setBacklight(uint8_t level) { displayBacklight(level); }

uint32_t BoardHal::heapFree() { return heap_caps_get_free_size(MALLOC_CAP_8BIT); }

uint32_t BoardHal::heapMin() { return heap_caps_get_minimum_free_size(MALLOC_CAP_8BIT); }

uint32_t BoardHal::batteryMv() { return analogReadMilliVolts(pins::kBattery) * 2; }  // 2:1 divider, assumed

bool BoardHal::ampOn() { return digitalRead(pins::kAmpEnable) == LOW; }

void BoardHal::say(const voice::Line& l) { audioSay(l); }
void BoardHal::cue(voice::Cue c, uint8_t vol) { audioCue(c, vol); }
void BoardHal::hush() { audioHush(); }
app::AudioOut BoardHal::audioOut() { return board::audioOut(); }

}  // namespace board
