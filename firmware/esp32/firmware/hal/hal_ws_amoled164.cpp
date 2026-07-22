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

void halFrameStats(uint32_t* avgUs, uint32_t* maxUs) {
  *avgUs = _frameAvgUs;
  *maxUs = _frameMaxUs;
}

void halPresent(BuddyCanvas& spr) {
  // Throttled to ~42fps: the face animates with per-frame easing, so the
  // present cadence is the visible frame rate. One present (rotate +
  // expand + streamed QSPI flush) costs ~13.4ms measured — see
  // halFrameStats — so a 24ms period leaves the loop ~45% of the core
  // for input/BLE/parse work.
  static uint32_t lastPush = 0;
  uint32_t now = millis();
  if (now - lastPush < 24) return;
  lastPush = now;
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
  const int BP = 8;                              // column-pairs per push
  static uint16_t batch[BP * 2 * PANEL_W];       // 8.75KB, internal RAM

  if (oy) {
    // Row 0 is shifted out this phase — blank it so no stale line parks.
    memset(batch, 0, (size_t)PANEL_W * 2);
    _gfx->draw16bitBeRGBBitmap(0, 0, batch, PANEL_W, 1);
  }

  // The 2x expand is EPX (Scale2x): each 2x2 output block is chosen from
  // the pixel's view-space neighbors, turning diagonal staircases into
  // smooth steps. EPX only ever copies existing colors — no blending —
  // so it can't band on the RGB332 palette and preserves the flat
  // glow-on-black art. Quadrant naming is in VIEW (landscape) space:
  // e0=top-left e1=top-right e2=bottom-left e3=bottom-right, with
  // A=up B=right C=left D=down; the rotation decides which panel
  // row/column each quadrant lands in (derived per orientation below).
  for (int b = 0; b < w; b += BP) {
    int n = (w - b < BP) ? (w - b) : BP;
    int yStart = 0;
    for (int j = 0; j < n; j++) {
      int i = b + j;
      int lx = WS_USB_LEFT ? (w - 1 - i) : i;   // ascending panel rows
      int base = (WS_USB_LEFT ? (PANEL_H - 2 - 2 * lx) : (2 * lx)) + oy;
      if (j == 0) yStart = base;
      uint16_t* rowF = batch + (size_t)j * 2 * PANEL_W;
      uint16_t* rowS = rowF + PANEL_W;
      if (ox) { rowF[0] = 0; rowS[0] = 0; }      // shifted-in left column
      const uint8_t* s = src + lx;
      bool hasL = lx > 0, hasR = lx < w - 1;
      for (int ly = 0; ly < h; ly++) {
        size_t o = (size_t)ly * stride;
        uint8_t P = s[o];
        uint8_t A = (ly > 0)     ? s[o - stride] : P;   // up (view)
        uint8_t D = (ly < h - 1) ? s[o + stride] : P;   // down
        int px = (WS_USB_LEFT ? (2 * ly) : (PANEL_W - 2 - 2 * ly)) + ox;
        bool p1 = px + 1 < PANEL_W;
        // Scale2x early-out: no rule can fire when up==down or
        // left==right, which covers flat runs and straight-edge
        // interiors — the vast majority of a glow-on-black frame. The
        // full neighbor read + rules only run near corners/diagonals.
        uint8_t C, B;
        if (A == D || (C = hasL ? s[o - 1] : P) == (B = hasR ? s[o + 1] : P)) {
          uint16_t c = _lut565[P];
          rowF[px] = c; rowS[px] = c;
          if (p1) { rowF[px + 1] = c; rowS[px + 1] = c; }
        } else {
          uint8_t e0 = P, e1 = P, e2 = P, e3 = P;
          if (C == A && A != B) e0 = A;
          if (A == B && B != D) e1 = B;
          if (D == C && C != A) e2 = C;
          if (B == D && D != C) e3 = D;
          if (WS_USB_LEFT) {
            // first panel row of the pair = view x-offset 1, px = view y
            rowF[px] = _lut565[e1]; if (p1) rowF[px + 1] = _lut565[e3];
            rowS[px] = _lut565[e0]; if (p1) rowS[px + 1] = _lut565[e2];
          } else {
            // first row = view x-offset 0, px order = view y reversed
            rowF[px] = _lut565[e2]; if (p1) rowF[px + 1] = _lut565[e0];
            rowS[px] = _lut565[e3]; if (p1) rowS[px + 1] = _lut565[e1];
          }
        }
      }
    }
    int rows = n * 2;
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
