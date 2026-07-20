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

static Arduino_DataBus* _bus = nullptr;
static Arduino_CO5300*  _gfx = nullptr;
static uint16_t* _fb = nullptr;        // 280x456 RGB565 in PSRAM
static uint16_t  _lut565[256];         // sprite RGB332 -> panel RGB565
static bool      _touchOk = false;
static bool      _touchDown = false;
static uint8_t   _brightness = 0;
static bool      _displayOn = true;

static void _buildLut() {
  for (int c = 0; c < 256; c++) {
    uint8_t r3 = (c >> 5) & 7, g3 = (c >> 2) & 7, b2 = c & 3;
    uint16_t r5 = (r3 * 31 + 3) / 7;
    uint16_t g6 = (g3 * 63 + 3) / 7;
    uint16_t b5 = (b2 * 31 + 1) / 3;
    _lut565[c] = (r5 << 11) | (g6 << 5) | b5;
  }
}

void halInit() {
  pinMode(PIN_BTN_BOOP,   INPUT_PULLUP);
  pinMode(PIN_BTN_REJECT, INPUT_PULLUP);
  pinMode(PIN_BTN_MENU,   INPUT_PULLUP);
  pinMode(PIN_BTN_BOOT,   INPUT_PULLUP);   // has an external pull-up too

  analogReadResolution(12);

  _buildLut();
  _fb = (uint16_t*)ps_malloc((size_t)PANEL_W * PANEL_H * 2);

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

void halPresent(BuddyCanvas& spr) {
  // Throttled: loop() calls this every ~16ms but a full frame is 255KB;
  // buddy animation ticks at 5fps and the fastest UI element (approval
  // wait counter) updates at 1Hz, so 25fps is plenty.
  static uint32_t lastPush = 0;
  uint32_t now = millis();
  if (now - lastPush < 40) return;
  lastPush = now;

  const uint8_t* src = (const uint8_t*)spr.getBuffer();
  if (!src || !_fb || !_gfx) return;
  int w = spr.width(), h = spr.height();
  if (w > HAL_W) w = HAL_W;
  if (h > HAL_H) h = HAL_H;
  // 8bpp rows may be padded for alignment; derive the real stride.
  size_t stride = (h > 0 && spr.bufferLength() >= (size_t)w * h)
                    ? spr.bufferLength() / h : (size_t)w;

  // AMOLED burn-in guard: drift the whole image by one physical pixel
  // through a 4-phase cycle (~45s per step) so no static UI edge parks on
  // a single OLED cell. Invisible at desk distance. The framebuffer is
  // cleared once per phase change; the shifted-in border rows stay black.
  // Phase 0 (ox=oy=0) covers every panel pixel, so the first frame fully
  // initializes the fresh ps_malloc buffer.
  static uint8_t drift = 0;
  static uint32_t nextDriftAt = 45000;
  if ((int32_t)(now - nextDriftAt) >= 0) {
    nextDriftAt = now + 45000;
    drift = (uint8_t)((drift + 1) & 3);
    memset(_fb, 0, (size_t)PANEL_W * PANEL_H * 2);
  }
  int ox = drift & 1, oy = (drift >> 1) & 1;

  // Rotate the 228x140 landscape logical canvas into the portrait panel
  // while pixel-doubling. Each logical COLUMN becomes two contiguous
  // panel ROWS, so the inner loop writes sequentially and the row can be
  // duplicated with one memcpy. With WS_USB_LEFT the USB-C connector
  // points left when facing the landscape screen; flip it if the
  // enclosure mounts the board the other way (image rotates 180°).
  for (int lx = 0; lx < w; lx++) {
    const uint8_t* s = src + lx;
    int py = (WS_USB_LEFT ? (PANEL_H - 2 - 2 * lx) : (2 * lx)) + oy;
    uint16_t* row = _fb + (size_t)py * PANEL_W;
    for (int ly = 0; ly < h; ly++) {
      uint16_t c = _lut565[s[(size_t)ly * stride]];
      int px = (WS_USB_LEFT ? (2 * ly) : (PANEL_W - 2 - 2 * ly)) + ox;
      row[px] = c;
      if (px + 1 < PANEL_W) row[px + 1] = c;
    }
    if (py + 1 < PANEL_H) memcpy(row + PANEL_W, row, (size_t)PANEL_W * 2);
  }
  _gfx->draw16bitRGBBitmap(0, 0, _fb, PANEL_W, PANEL_H);
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
