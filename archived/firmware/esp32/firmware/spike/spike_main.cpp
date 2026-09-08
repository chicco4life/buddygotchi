// Bring-up spike for the Waveshare ESP32-S3-Touch-AMOLED-1.64.
// Flash with:  pio run -e ws-amoled164-spike -t upload
//
// Deliberately runs through the production HAL (same init, same
// RGB332->565 2x-expand present path) so a pass here validates exactly
// what the real firmware will do. Sequence:
//
//   1. full-screen R / G / B / W fills, 1.5s each — panel init, colors,
//      byte order (red must look red; blue-ish red = byte-swap bug)
//   2. 1px white border + center crosshair, 5s — the border must be
//      visible on ALL FOUR edges; a clipped/shifted edge means the 20px
//      column offset is wrong
//   3. brightness ramp 0->255 over the border screen — panel must go
//      dark->bright smoothly (DCS 0x51 path)
//   4. live status screen forever: button states, touch, battery mV,
//      heap, uptime — also streamed to serial once a second
//
// Everything also logs over USB CDC, so a dead panel still tells you the
// board is alive via `pio device monitor`.
#include <Arduino.h>
#include "../hal/hal.h"

SET_LOOP_TASK_STACK_SIZE(16384);

static BuddyCanvas spr(HAL_CANVAS_PARENT);

static void present() {
  // The HAL throttles to 25fps; spin briefly so each staged frame lands.
  uint32_t until = millis() + 60;
  while (millis() < until) { halPresent(spr); delay(5); }
}

static void fill(uint16_t c, const char* name) {
  Serial.printf("[spike] fill %s\n", name);
  spr.fillSprite(c);
  present();
  delay(1500);
}

static void borderScreen() {
  spr.fillSprite(0x0000);
  spr.drawRect(0, 0, HAL_W, HAL_H, 0xFFFF);
  spr.drawFastHLine(HAL_W / 2 - 10, HAL_H / 2, 20, 0xF800);
  spr.drawFastVLine(HAL_W / 2, HAL_H / 2 - 10, 20, 0xF800);
  spr.setTextColor(0xFFFF, 0x0000);
  spr.setCursor(10, 10);
  spr.print("border check");
  present();
}

void setup() {
  Serial.begin(115200);
  delay(2000);   // native CDC enumerates async; give the host a moment
  Serial.println("[spike] ws-amoled164 bring-up");

  halInit();
  spr.setColorDepth(8);
  spr.createSprite(HAL_W, HAL_H);
  halSetBrightness(200);

  fill(0xF800, "RED");
  fill(0x07E0, "GREEN");
  fill(0x001F, "BLUE");
  fill(0xFFFF, "WHITE");

  Serial.println("[spike] border check — all 4 edges must be visible");
  borderScreen();
  delay(5000);

  Serial.println("[spike] brightness ramp");
  for (int b = 0; b <= 255; b += 5) { halSetBrightness(b); delay(40); }
  halSetBrightness(200);
}

void loop() {
  static uint32_t nextLog = 0;
  halUpdate();

  bool boop = halButtonDown(HAL_BTN_BOOP);
  bool rej  = halButtonDown(HAL_BTN_REJECT);
  bool menu = halButtonDown(HAL_BTN_MENU);
  int mv    = halBatteryVoltage_mV();

  spr.fillSprite(0x0000);
  spr.drawRect(0, 0, HAL_W, HAL_H, 0x8410);
  spr.setTextColor(0xFFFF, 0x0000);
  spr.setCursor(8, 12);   spr.print("spike: live");
  spr.setTextColor(boop ? 0x07E0 : 0x8410, 0x0000);
  spr.setCursor(8, 36);   spr.printf("BOOP   %s", boop ? "DOWN" : "up");
  spr.setTextColor(rej ? 0xF800 : 0x8410, 0x0000);
  spr.setCursor(8, 48);   spr.printf("REJECT %s", rej ? "DOWN" : "up");
  spr.setTextColor(menu ? 0x07FF : 0x8410, 0x0000);
  spr.setCursor(8, 60);   spr.printf("MENU   %s", menu ? "DOWN" : "up");
  spr.setTextColor(0xFFFF, 0x0000);
  spr.setCursor(8, 84);   spr.printf("bat %d mV", mv);
  spr.setCursor(8, 96);   spr.printf("chg %s", halIsCharging() ? "yes" : "no");
  spr.setCursor(8, 120);  spr.printf("heap %lu", (unsigned long)ESP.getFreeHeap());
  spr.setCursor(8, 132);  spr.printf("up   %lus", (unsigned long)(millis() / 1000));
  halPresent(spr);

  if (millis() >= nextLog) {
    nextLog = millis() + 1000;
    Serial.printf("[spike] boop=%d rej=%d menu=%d bat=%dmV chg=%d heap=%lu\n",
                  boop, rej, menu, mv, halIsCharging(),
                  (unsigned long)ESP.getFreeHeap());
  }
  delay(10);
}
