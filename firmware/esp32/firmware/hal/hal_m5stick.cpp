#ifndef BOARD_WS_AMOLED_164
// M5StickC Plus 2 board implementation — a straight extraction of the
// StickCP2 calls that used to live inline in main.cpp/data.h/xfer.h/ota.h.
// Behavior is intentionally identical to the pre-HAL firmware.
#include "hal.h"

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
bool halIsCharging()        { return StickCP2.Power.isCharging(); }
void halSetLed(bool on)     { StickCP2.Power.setLed(on ? 1 : 0); }
void halTone(uint16_t freq, uint16_t ms) { StickCP2.Speaker.tone(freq, ms); }

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
