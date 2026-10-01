// The screen on the Waveshare ESP32-S3-Touch-AMOLED-2.06 (documentation/DEVICE.md §9):
// the CO5300 through LovyanGFX on quad SPI. The canvas is drawn 1.5 times
// as large and turned a quarter as it's pushed (board/config.h).
#include "board/display.h"

#define LGFX_USE_V1
#include <Arduino.h>
#include <LovyanGFX.hpp>
#include <esp_heap_caps.h>

#include <algorithm>

#include "board/config.h"
#include "render/palette.h"

namespace board {
namespace {

class Panel : public lgfx::LGFX_Device {
 public:
  Panel() {
    {
      auto cfg = bus_.config();
      cfg.spi_host = SPI2_HOST;
      cfg.spi_mode = 0;
      cfg.freq_write = kSpiWriteHz;
      cfg.freq_read = 16000000;
      cfg.spi_3wire = true;
      cfg.use_lock = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = pins::kLcdSclk;
      cfg.pin_mosi = -1;
      cfg.pin_miso = -1;
      cfg.pin_dc = -1;
      cfg.pin_io0 = pins::kLcdIo0;
      cfg.pin_io1 = pins::kLcdIo1;
      cfg.pin_io2 = pins::kLcdIo2;
      cfg.pin_io3 = pins::kLcdIo3;
      bus_.config(cfg);
      panel_.setBus(&bus_);
    }
    {
      auto cfg = panel_.config();
      cfg.pin_cs = pins::kLcdCs;
      cfg.pin_rst = -1;  // reset in displayBegin, held longer than LovyanGFX holds it
      cfg.pin_busy = -1;
      cfg.memory_width = kPanelWidth;
      cfg.memory_height = kPanelHeight;
      cfg.panel_width = kPanelWidth;
      cfg.panel_height = kPanelHeight;
      cfg.offset_x = kPanelOffsetX;
      cfg.offset_y = 0;
      cfg.offset_rotation = 0;
      cfg.readable = false;
      cfg.invert = false;
      cfg.rgb_order = false;
      cfg.dlen_16bit = false;
      cfg.bus_shared = false;
      panel_.config(cfg);
    }
    setPanel(&panel_);
  }

 private:
  lgfx::Bus_SPI bus_;
  lgfx::Panel_CO5300 panel_;
};

// Two bands of the canvas (12 rows) are 18 panel columns, even as the
// CO5300 wants; one batch is at most 18 × 480 px, 17.3 KB.
constexpr int kRows = 2 * render::kBand;
constexpr int kCols = kRows * 3 / 2;
static_assert(render::kBand * 3 % 2 == 0 && (render::kHeight / kRows) * kRows == render::kHeight,
              "two bands must scale to whole, even panel columns");

Panel lcd;
uint16_t* buf[2] = {nullptr, nullptr};
uint16_t swapped[256];  // palette in the panel's byte order
uint16_t along[kPicH];  // panel step along the canvas's columns → canvas column
uint16_t across[kPicW]; // panel step across → canvas row
render::Changes changes;

// The CO5300's hardware reset, timed as Waveshare's own driver times it
// (Arduino_GFX's CO5300, 200 ms each way). LovyanGFX's 8 ms low and 64 ms
// after were enough from power-up but, after a restart over USB with the
// panel still powered, left it stuck on a white screen until the board
// was unplugged (DEVICE.md §9).
constexpr uint32_t kResetMs = 200;

void resetPanel() {
  pinMode(pins::kLcdReset, OUTPUT);
  digitalWrite(pins::kLcdReset, HIGH);
  delay(10);
  digitalWrite(pins::kLcdReset, LOW);
  delay(kResetMs);
  digitalWrite(pins::kLcdReset, HIGH);
  delay(kResetMs);
}

}  // namespace

bool displayBegin() {
  for (int i = 0; i < 2; ++i) {
    buf[i] = static_cast<uint16_t*>(heap_caps_malloc(kCols * kPicH * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL));
    if (!buf[i]) return false;
  }
  for (int i = 0; i < 256; ++i) {
    uint16_t c = render::paletteAt(i);
    swapped[i] = uint16_t((c << 8) | (c >> 8));
  }
  for (int i = 0; i < kPicH; ++i) along[i] = uint16_t(i * 2 / 3);
  for (int j = 0; j < kPicW; ++j) across[j] = uint16_t(j * 2 / 3);
  resetPanel();
  if (!lcd.init()) return false;
  lcd.setRotation(0);
  lcd.fillScreen(0);
  lcd.setBrightness(255);
  return true;
}

void displayPush(const render::Canvas& canvas) {
  int cur = 0;
  lcd.startWrite();
  for (int p = 0; p < render::kHeight / kRows; ++p) {
    render::Span a = changes.band(canvas, 2 * p), b = changes.band(canvas, 2 * p + 1);
    if (a.empty() && b.empty()) continue;
    int x0 = a.empty() ? b.x0 : b.empty() ? a.x0 : std::min(a.x0, b.x0);
    int x1 = a.empty() ? b.x1 : b.empty() ? a.x1 : std::max(a.x1, b.x1);
    // The canvas columns [x0, x1) cover panel steps [i0, i1), widened to even.
    int i0 = (3 * x0 + 1) / 2 & ~1, i1 = std::min(kPicH, ((3 * x1 + 1) / 2 + 1) & ~1);
    int px = kTopOnPanelLeft ? kPicX + kCols * p : kPicX + kPicW - kCols * (p + 1);
    int py = kTopOnPanelLeft ? kPicY + kPicH - i1 : kPicY + i0;
    uint16_t* dst = buf[cur];
    for (int k = 0; k < i1 - i0; ++k) {
      int i = kTopOnPanelLeft ? i1 - 1 - k : i0 + k;
      const uint8_t* col = canvas.pixels() + along[i];
      for (int c = 0; c < kCols; ++c) {
        int j = kTopOnPanelLeft ? kCols * p + c : kCols * p + kCols - 1 - c;
        *dst++ = swapped[col[across[j] * render::kWidth]];
      }
    }
    lcd.setAddrWindow(px, py, kCols, i1 - i0);
    lcd.writePixelsDMA(buf[cur], kCols * (i1 - i0), false);  // already in panel order
    cur ^= 1;
  }
  lcd.endWrite();
}

void displayBacklight(uint8_t level) { lcd.setBrightness(level); }

void displayFailed() {}  // an AMOLED has no backlight to leave on

}  // namespace board
