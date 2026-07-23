#ifdef BOARD_WS_AMOLED_164
// Waveshare ESP32-S3-Touch-AMOLED-1.64 board implementation.
//
// Display: 1.64" AMOLED 280x456, CO5300 controller (SH8601-compatible
// command set) over QSPI. Driven with Arduino_GFX's Arduino_CO5300 —
// the stack two independent community ports of this exact board use.
// Panel quirks this file owns so nobody else has to care:
//   - controller RAM column offset of 20px (passed to the panel class)
//   - draw windows must be 2-pixel aligned -> we only ever flush the
//     full 280x456 frame, which is always aligned
//   - no TE signal routed -> no vsync; full-frame flush minimizes tearing
//   - brightness is DCS 0x51 over QSPI (there is no backlight pin) and
//     the panel powers up at brightness 0
//   - hardware rotation is broken on this controller; portrait only
//
// Touch: FT3168 @ I2C 0x38, SDA=47 SCL=48. INT/RST are not routed on this
// board, so we poll. Touch is surfaced via halTouchDown() only — never as
// the BOOP button, so a screen tap can't answer a permission prompt.
// Battery: no PMIC — voltage only, via a /3 divider on GPIO4 (ADC1_CH3).
#include "hal.h"
#include <Arduino_GFX_Library.h>
#include <Wire.h>
#include <esp_sleep.h>
#include <esp_bt.h>
#include <driver/gpio.h>

static const int PANEL_W = 280;
static const int PANEL_H = 456;

// Landscape mounting direction: true = USB-C points left when you face
// the landscape screen (board rotated 90° clockwise into the enclosure).
static const bool WS_USB_LEFT = true;

// Display pins (Waveshare schematic / official arduino-esp32 variant)
static const int PIN_OLED_CS  = 9;
static const int PIN_OLED_CLK = 10;
static const int PIN_OLED_D0  = 11;
static const int PIN_OLED_D1  = 12;
static const int PIN_OLED_D2  = 13;
static const int PIN_OLED_D3  = 14;
static const int PIN_OLED_RST = 21;

// Buttons: external momentaries to GND on header P1 (IO1/IO2/IO5 avoid the
// S3 strapping pins 3/45/46). BOOT (IO0) doubles as BOOP so the board is
// fully usable before anything is soldered.
static const int PIN_BTN_BOOP   = 1;
static const int PIN_BTN_REJECT = 2;
static const int PIN_BTN_MENU   = 5;
static const int PIN_BTN_BOOT   = 0;

static const int PIN_TP_SDA  = 47;
static const int PIN_TP_SCL  = 48;
static const int TP_ADDR     = 0x38;
static const int PIN_BAT_ADC = 4;

// QMI8658C IMU, same I2C bus as the touch panel. INT1 (GPIO46) is not
// used — we poll, like touch. Address depends on the SA0 strap; probe
// both (0x6A first — the Waveshare schematic's nominal wiring).
static int IMU_ADDR = 0x6A;

static Arduino_DataBus* _bus = nullptr;
static Arduino_CO5300*  _gfx = nullptr;
static uint16_t  _lut565[256];         // sprite RGB332 -> panel RGB565
static bool      _touchOk = false;
static bool      _touchDown = false;
static bool      _imuOk = false;
static uint8_t   _brightness = 0;
static bool      _displayOn = true;

// Full-stop register write (the repeated-start path is what made the
// touch poll flaky on the core-3 i2c-ng driver; see halUpdate).
static bool _i2cWriteReg(int addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission(true) == 0;
}

static bool _i2cReadRegs(int addr, uint8_t reg, uint8_t* buf, size_t n) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(true) != 0) return false;
  if (Wire.requestFrom(addr, (int)n) != (int)n) return false;
  for (size_t i = 0; i < n; i++) buf[i] = (uint8_t)Wire.read();
  return true;
}

static void _buildLut() {
  for (int c = 0; c < 256; c++) {
    uint8_t r3 = (c >> 5) & 7, g3 = (c >> 2) & 7, b2 = c & 3;
    uint16_t r5 = (r3 * 31 + 3) / 7;
    uint16_t g6 = (g3 * 63 + 3) / 7;
    uint16_t b5 = (b2 * 31 + 1) / 3;
    // Stored BYTE-SWAPPED (big-endian): the panel wants MSB first, and
    // pre-swapping here lets halPresent use draw16bitBeRGBBitmap, which
    // skips Arduino_GFX's per-pixel CPU swap pass on every push.
    uint16_t v = (uint16_t)((r5 << 11) | (g6 << 5) | b5);
    _lut565[c] = (uint16_t)((v << 8) | (v >> 8));
  }
}

void halInit() {
  pinMode(PIN_BTN_BOOP,   INPUT_PULLUP);
  pinMode(PIN_BTN_REJECT, INPUT_PULLUP);
  pinMode(PIN_BTN_MENU,   INPUT_PULLUP);
  pinMode(PIN_BTN_BOOT,   INPUT_PULLUP);   // has an external pull-up too

  analogReadResolution(12);

  _buildLut();

  _bus = new Arduino_ESP32QSPI(PIN_OLED_CS, PIN_OLED_CLK,
                               PIN_OLED_D0, PIN_OLED_D1, PIN_OLED_D2, PIN_OLED_D3);
  // col_offset1=20: the 280px window sits at x=20 in the controller's RAM.
  _gfx = new Arduino_CO5300(_bus, PIN_OLED_RST, 0 /* rotation */,
                            PANEL_W, PANEL_H, 20, 0, 0, 0);
  _gfx->begin(80000000L);
  _gfx->fillScreen(0x0000);
  _gfx->setBrightness(0);   // panel powers up dark; main sets the real level

  // FT3168 touch — probe so a flaky/absent panel degrades to buttons-only.
  // 300kHz: the chip tops out at 400k and the Waveshare demo runs 300k;
  // at 400k the core-3 i2c-ng driver throws sporadic ESP_ERR_INVALID_STATE.
  Wire.begin(PIN_TP_SDA, PIN_TP_SCL, 300000);
  Wire.beginTransmission(TP_ADDR);
  _touchOk = (Wire.endTransmission() == 0);
  if (!_touchOk) Serial.println("[hal] FT3168 not responding — touch disabled");

  // QMI8658 accel bring-up: find the chip (SA0 strap picks 0x6A/0x6B),
  // verify WHO_AM_I (0x05), then address auto-increment (CTRL1), ±4g @
  // 125Hz (CTRL2), accel enable (CTRL7). A flaky/absent chip degrades to
  // no motion features, like touch.
  for (int addr : { 0x6A, 0x6B }) {
    uint8_t who = 0;
    bool seen = _i2cReadRegs(addr, 0x00, &who, 1);
    Serial.printf("[hal] QMI8658 probe 0x%02X: %s who=0x%02X\n",
                  addr, seen ? "ack" : "nack", who);
    if (seen && who == 0x05) {
      IMU_ADDR = addr;
      _imuOk = _i2cWriteReg(addr, 0x02, 0x40) &&
               _i2cWriteReg(addr, 0x03, 0x16) &&
               _i2cWriteReg(addr, 0x08, 0x01);
      break;
    }
  }
  if (!_imuOk) Serial.println("[hal] QMI8658 not responding — motion disabled");
}

void halUpdate() {
  // Poll touch at ~30ms. Register 0x02 = active touch count (FocalTech
  // standard map). Treated as a held BOOP button.
  //
  // Full-stop write-then-read: the core-3 driver's repeated-start path
  // (endTransmission(false) + requestFrom) fails sporadically with
  // ESP_ERR_INVALID_STATE and logs an error each time; FocalTech register
  // reads are fine with a stop in between. On failure, back off so a bad
  // patch doesn't log at 30ms cadence, and re-init the bus after repeated
  // failures in case it's wedged.
  static uint32_t nextPoll = 0;
  static uint8_t fails = 0;
  if (!_touchOk) return;
  uint32_t now = millis();
  if ((int32_t)(now - nextPoll) < 0) return;
  nextPoll = now + 30;
  Wire.beginTransmission(TP_ADDR);
  Wire.write(0x02);
  bool ok = Wire.endTransmission(true) == 0 && Wire.requestFrom(TP_ADDR, 1) == 1;
  if (!ok) {
    _touchDown = false;
    nextPoll = now + 250;
    if (++fails >= 8) {
      fails = 0;
      Wire.end();
      Wire.begin(PIN_TP_SDA, PIN_TP_SCL, 300000);
    }
    return;
  }
  fails = 0;
  uint8_t n = Wire.read() & 0x0F;
  _touchDown = (n > 0 && n <= 5);
}

static uint32_t _frameAvgUs = 0;
static uint32_t _frameMaxUs = 0;
static uint32_t _lastPush = 0;

void halFrameStats(uint32_t* avgUs, uint32_t* maxUs) {
  *avgUs = _frameAvgUs;
  *maxUs = _frameMaxUs;
}

bool halPresentDue() { return millis() - _lastPush >= 24; }

void halPresent(BuddyCanvas& spr) {
  // Throttled to ~42fps: the face animates with per-frame easing, so the
  // present cadence is the visible frame rate (see halFrameStats for the
  // measured cost of one rotate + streamed QSPI flush).
  uint32_t now = millis();
  if (now - _lastPush < 24) return;
  _lastPush = now;
  uint32_t t0 = micros();

  const uint8_t* src = (const uint8_t*)spr.getBuffer();
  if (!src || !_gfx) return;
  int w = spr.width(), h = spr.height();
  if (w > HAL_W) w = HAL_W;
  if (h > HAL_H) h = HAL_H;
  // 8bpp rows may be padded for alignment; derive the real stride.
  size_t stride = (h > 0 && spr.bufferLength() >= (size_t)w * h)
                    ? spr.bufferLength() / h : (size_t)w;

  // AMOLED burn-in guard: drift the whole image by one physical pixel
  // through a 4-phase cycle (~45s per step) so no static UI edge parks on
  // a single OLED cell. Invisible at desk distance. Shifted-in border
  // cells are blanked explicitly each frame (there is no persistent
  // framebuffer to memset anymore).
  static uint8_t drift = 0;
  static uint32_t nextDriftAt = 45000;
  if ((int32_t)(now - nextDriftAt) >= 0) {
    nextDriftAt = now + 45000;
    drift = (uint8_t)((drift + 1) & 3);
  }
  int ox = drift & 1, oy = (drift >> 1) & 1;

  // Rotate the 228x140 landscape logical canvas into the portrait panel
  // while pixel-doubling, streamed through a small INTERNAL-RAM batch
  // buffer straight to the controller. The previous PSRAM framebuffer
  // cost a full 255KB write + 255KB read-back per frame (~34ms measured);
  // streaming cuts the frame to sprite-reads + one 255KB QSPI push.
  // Each logical COLUMN becomes two contiguous panel ROWS; iterating
  // columns in panel order makes every batch a contiguous ascending
  // window. With WS_USB_LEFT the USB-C connector points left when facing
  // the landscape screen; flip it if the enclosure mounts the board the
  // other way (image rotates 180°).
  const int BP = 16;                             // panel rows per push
  static uint16_t batch[BP * PANEL_W];           // 8.75KB, internal RAM

  if (oy) {
    // Row 0 is shifted out this phase — blank it so no stale line parks.
    memset(batch, 0, (size_t)PANEL_W * 2);
    _gfx->draw16bitBeRGBBitmap(0, 0, batch, PANEL_W, 1);
  }

  // Native-resolution rotate: one logical COLUMN is one panel ROW, no
  // scaling. Batches of BP consecutive columns are consecutive ascending
  // panel rows, streamed through the internal buffer. Reading BP
  // consecutive sprite columns per panel row keeps the (PSRAM) sprite
  // reads within shared cache lines.
  for (int b = 0; b < w; b += BP) {
    int n = (w - b < BP) ? (w - b) : BP;
    int yStart = b + oy;
    for (int j = 0; j < n; j++) {
      int i = b + j;
      int lx = WS_USB_LEFT ? (w - 1 - i) : i;   // ascending panel rows
      uint16_t* row = batch + (size_t)j * PANEL_W;
      if (ox) row[0] = 0;                        // shifted-in left column
      const uint8_t* s = src + lx;
      for (int ly = 0; ly < h; ly++) {
        int px = (WS_USB_LEFT ? ly : (PANEL_W - 1 - ly)) + ox;
        if (px < PANEL_W) row[px] = _lut565[s[(size_t)ly * stride]];
      }
    }
    int rows = n;
    if (yStart + rows > PANEL_H) rows = PANEL_H - yStart;
    if (rows > 0) _gfx->draw16bitBeRGBBitmap(0, yStart, batch, PANEL_W, rows);
  }

  uint32_t total = micros() - t0;
  _frameAvgUs += ((int32_t)(total - _frameAvgUs)) >> 3;
  if (total > _frameMaxUs) _frameMaxUs = total;
}

void halDisplaySleep() {
  if (!_gfx) return;
  _gfx->setBrightness(0);
  _gfx->displayOff();
  _displayOn = false;
}

void halDisplayWake() {
  if (!_gfx) return;
  _gfx->displayOn();
  _gfx->setBrightness(_brightness);
  _displayOn = true;
}

void halSetBrightness(uint8_t b) {
  _brightness = b;
  if (_gfx && _displayOn) _gfx->setBrightness(b);
}

// 1 = landscape logical canvas (the panel itself is portrait; the rotate
// happens in halPresent). Host tooling only uses this as metadata.
int halDisplayRotation() { return 1; }

bool halButtonDown(HalButton b) {
  switch (b) {
    case HAL_BTN_BOOP:
      // Touch is deliberately excluded: only a physical press may
      // approve. See halTouchDown().
      return digitalRead(PIN_BTN_BOOP) == LOW ||
             digitalRead(PIN_BTN_BOOT) == LOW;
    case HAL_BTN_REJECT: return digitalRead(PIN_BTN_REJECT) == LOW;
    case HAL_BTN_MENU:   return digitalRead(PIN_BTN_MENU) == LOW;
    default:             return false;
  }
}

bool halHasButton(HalButton b) { (void)b; return true; }

bool halTouchDown() { return _touchDown; }

int halBatteryVoltage_mV() {
  // 200K/100K divider -> ADC sees vbat/3. Average a few reads; the S3 ADC
  // is noisy and this feeds a percentage estimate, not telemetry.
  uint32_t sum = 0;
  for (int i = 0; i < 4; i++) sum += analogReadMilliVolts(PIN_BAT_ADC);
  return (int)(sum / 4) * 3;
}

int halBatteryCurrent_mA() { return 0; }

bool halIsCharging() {
  // No charge-status GPIO on this board. At the ETA6098's CV level the
  // pack reads ~4.3V+, which only happens on USB power — good enough for
  // the OTA "don't die mid-flash" gate.
  return halBatteryVoltage_mV() >= 4300;
}

void halSetLed(bool on) { (void)on; }
void halTone(uint16_t freq, uint16_t ms) { (void)freq; (void)ms; }

bool halImuRead(float* ax, float* ay, float* az) {
  static uint32_t backoffUntil = 0;
  if (!_imuOk) return false;
  uint32_t now = millis();
  if ((int32_t)(now - backoffUntil) < 0) return false;
  uint8_t raw[6];
  if (!_i2cReadRegs(IMU_ADDR, 0x35, raw, 6)) {   // AX_L..AZ_H
    // The shared bus throws sporadic i2c-ng INVALID_STATE (see the touch
    // poll, which owns bus re-init). Back off so a bad patch isn't
    // hammered at 20Hz — each failure logs a driver error line, and that
    // serial spam alone makes the whole device feel glitchy.
    backoffUntil = now + 500;
    return false;
  }
  const float LSB_PER_G = 8192.0f;   // ±4g full scale
  *ax = (int16_t)(raw[0] | (raw[1] << 8)) / LSB_PER_G;
  *ay = (int16_t)(raw[2] | (raw[3] << 8)) / LSB_PER_G;
  *az = (int16_t)(raw[4] | (raw[5] << 8)) / LSB_PER_G;
  return true;
}

void halDeepSleep(uint32_t timerWakeMs) {
  halDisplaySleep();
  Serial.flush();
  // Light sleep, not deep: the only wake button is BOOT (GPIO0), a
  // strapping pin — a deep-sleep wake samples the straps while the finger
  // is still down and can drop the ROM into download mode (GPIO46, the
  // other strap half, floats on the IMU INT line). Light sleep resumes
  // without a strap sample; we esp_restart() after it for a clean stack
  // (the BLE link is long dead by then anyway).
  gpio_wakeup_enable((gpio_num_t)PIN_BTN_BOOT, GPIO_INTR_LOW_LEVEL);
  esp_sleep_enable_gpio_wakeup();
  if (timerWakeMs > 0) esp_sleep_enable_timer_wakeup((uint64_t)timerWakeMs * 1000ULL);
  // Kill the radio at the controller level (no host-structure frees — see
  // bleStop) so light sleep isn't blocked by the BT power-management lock.
  // The narrow window before sleep entry is safe: tasks freeze in light
  // sleep and we esp_restart() on wake before the host notices.
  if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
    esp_bt_controller_disable();
  }
  esp_light_sleep_start();
  // Wait out the wake press before restarting: the ROM re-reads the GPIO0
  // strap on any reset, and restarting under a still-held finger would
  // boot the serial downloader instead of the app.
  uint32_t t0 = millis();
  while (digitalRead(PIN_BTN_BOOT) == LOW && millis() - t0 < 5000) delay(10);
  delay(50);
  esp_restart();
}

void halSetLocalTime(const struct tm& lt) {
  // No RTC chip: hold the bridge's local time in the system clock. TZ is
  // unset (UTC), so mktime-on-gmtime round-trips the components exactly.
  struct tm tmp = lt;
  time_t t = mktime(&tmp);
  if (t == (time_t)-1) return;
  struct timeval tv = { .tv_sec = t, .tv_usec = 0 };
  settimeofday(&tv, nullptr);
}
#endif  // BOARD_WS_AMOLED_164
