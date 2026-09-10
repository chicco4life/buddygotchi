#ifndef BOARD_WS_AMOLED_164
// M5StickC Plus 2 board implementation — a straight extraction of the
// StickCP2 calls that used to live inline in main.cpp/data.h/xfer.h/ota.h.
// Behavior is intentionally identical to the pre-HAL firmware.
#include "hal.h"
#include <esp_sleep.h>

void halInit() {
  auto cfg = M5.config();
  StickCP2.begin(cfg);
  StickCP2.Display.setRotation(0);
  StickCP2.Speaker.begin();
  StickCP2.Power.setLed(0);   // red LED, active-low — off
}

void halUpdate() { StickCP2.update(); }

void halPresent(BuddyCanvas& spr) { spr.pushSprite(0, 0); }

void halDisplaySleep() { StickCP2.Display.sleep(); }
void halDisplayWake()  { StickCP2.Display.wakeup(); }
void halSetBrightness(uint8_t b) { StickCP2.Display.setBrightness(b); }
int  halDisplayRotation() { return StickCP2.Display.getRotation(); }

// Input-only pins with external pull-ups; LOW = pressed. No pinMode needed.
bool halButtonDown(HalButton b) {
  switch (b) {
    case HAL_BTN_BOOP:   return digitalRead(37) == LOW;
    case HAL_BTN_REJECT: return digitalRead(39) == LOW;
    default:             return false;
  }
}

bool halHasButton(HalButton b) { return b != HAL_BTN_MENU; }

int  halBatteryVoltage_mV() { return StickCP2.Power.getBatteryVoltage(); }
int  halBatteryCurrent_mA() { return (int)StickCP2.Power.getBatteryCurrent(); }
bool halTouchDown()         { return false; }   // no touchscreen on M5
bool halTouchPoint(int* x, int* y) { (void)x; (void)y; return false; }
bool halTouchReady()        { return false; }
bool halImuReady()          { return false; }
void halTouchStats(uint32_t* avgUs, uint32_t* maxUs) { *avgUs = 0; *maxUs = 0; }
bool halPresentDue()        { return true; }    // M5 presents every loop
void halFrameStats(uint32_t* avgUs, uint32_t* maxUs) { *avgUs = 0; *maxUs = 0; }
bool halIsCharging()        { return StickCP2.Power.isCharging(); }
void halSetLed(bool on)     { StickCP2.Power.setLed(on ? 1 : 0); }
void halSilence() { StickCP2.Speaker.stop(); }
void halTone(uint16_t freq, uint16_t ms) { StickCP2.Speaker.tone(freq, ms); }

// The Plus2's MPU6886 isn't wired up here yet — the Pebble is the board
// that carries motion features; the M5 stays the pre-HAL regression rig.
bool halImuRead(float* ax, float* ay, float* az) {
  (void)ax; (void)ay; (void)az;
  return false;
}

void halDeepSleep(uint32_t timerWakeMs) {
  StickCP2.Display.sleep();
  Serial.flush();
  // BtnA (GPIO37, RTC-capable, external pull-up, NOT a strapping pin) can
  // wake a true deep sleep safely. Original-ESP32 EXT1 has no ANY_LOW
  // mode; ALL_LOW on a single pin is the same thing.
  esp_sleep_enable_ext1_wakeup(1ULL << 37, ESP_EXT1_WAKEUP_ALL_LOW);
  if (timerWakeMs > 0) esp_sleep_enable_timer_wakeup((uint64_t)timerWakeMs * 1000ULL);
  esp_deep_sleep_start();
}

void halSetLocalTime(const struct tm& lt) {
  m5::rtc_time_t tm;
  tm.hours = lt.tm_hour; tm.minutes = lt.tm_min; tm.seconds = lt.tm_sec;
  m5::rtc_date_t dt;
  dt.weekDay = lt.tm_wday; dt.month = lt.tm_mon + 1;
  dt.date = lt.tm_mday; dt.year = lt.tm_year + 1900;
  StickCP2.Rtc.setTime(&tm);
  StickCP2.Rtc.setDate(&dt);
}
#endif  // !BOARD_WS_AMOLED_164
