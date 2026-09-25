#include "board/display.h"

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include <esp_heap_caps.h>

#include "board/pins.h"
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
      cfg.spi_3wire = false;
      cfg.use_lock = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = pins::kLcdSclk;
      cfg.pin_mosi = pins::kLcdMosi;
      cfg.pin_miso = -1;
      cfg.pin_dc = pins::kLcdDc;
      bus_.config(cfg);
      panel_.setBus(&bus_);
    }
    {
      auto cfg = panel_.config();
      cfg.pin_cs = pins::kLcdCs;
      cfg.pin_rst = -1;  // shared with EN; the ST7789 gets a software reset
      cfg.pin_busy = -1;
      cfg.memory_width = render::kWidth;
      cfg.memory_height = render::kHeight;
      cfg.panel_width = render::kWidth;
      cfg.panel_height = render::kHeight;
      cfg.offset_x = 0;
      cfg.offset_y = 0;
      cfg.offset_rotation = 0;
      cfg.readable = false;
      cfg.invert = kInvert;
      cfg.rgb_order = kBgr;
      cfg.dlen_16bit = false;
      cfg.bus_shared = false;
      panel_.config(cfg);
    }
    {
      auto cfg = light_.config();
      cfg.pin_bl = pins::kBacklight;
      cfg.invert = false;
      cfg.freq = 12000;  // at least 5 kHz, or it flickers (DEVICE.md §8)
      cfg.pwm_channel = 7;
      light_.config(cfg);
      panel_.setLight(&light_);
    }
    {
      auto cfg = touch_.config();
      cfg.x_min = 200;
      cfg.x_max = 3900;
      cfg.y_min = 200;
      cfg.y_max = 3900;
      cfg.pin_int = pins::kTouchIrq;
      cfg.bus_shared = false;
      cfg.offset_rotation = 0;
      cfg.spi_host = SPI3_HOST;
      cfg.freq = 1000000;
      cfg.pin_sclk = pins::kTouchSclk;
      cfg.pin_mosi = pins::kTouchMosi;
      cfg.pin_miso = pins::kTouchMiso;
      cfg.pin_cs = pins::kTouchCs;
      touch_.config(cfg);
      panel_.setTouch(&touch_);
    }
    setPanel(&panel_);
  }

 private:
  lgfx::Bus_SPI bus_;
  lgfx::Panel_ST7789 panel_;
  lgfx::Light_PWM light_;
  lgfx::Touch_XPT2046 touch_;
};

constexpr int kBand = 16;  // rows per DMA batch (DEVICE.md §6)

Panel lcd;
uint16_t* band[2] = {nullptr, nullptr};
uint16_t swapped[256];  // palette in the panel's byte order
uint32_t hashes[render::kHeight];
bool pushedOnce = false;

}  // namespace

bool displayBegin() {
  for (int i = 0; i < 2; ++i) {
    band[i] = static_cast<uint16_t*>(heap_caps_malloc(render::kWidth * kBand * 2, MALLOC_CAP_DMA));
    if (!band[i]) return false;
  }
  for (int i = 0; i < 256; ++i) {
    uint16_t c = render::paletteAt(i);
    swapped[i] = uint16_t((c << 8) | (c >> 8));
  }
  if (!lcd.init()) return false;
  lcd.setRotation(kRotation);
  lcd.setBrightness(255);
  return true;
}

int displayPush(const render::Canvas& canvas) {
  int sent = 0, cur = 0;
  lcd.startWrite();
  for (int y0 = 0; y0 < render::kHeight; y0 += kBand) {
    bool changed = !pushedOnce;
    for (int y = y0; y < y0 + kBand; ++y) {
      uint32_t h = canvas.rowHash(y);
      if (h != hashes[y]) changed = true;
      hashes[y] = h;
    }
    if (!changed) continue;
    const uint8_t* src = canvas.pixels() + y0 * render::kWidth;
    uint16_t* dst = band[cur];
    for (int i = 0; i < render::kWidth * kBand; ++i) {
      dst[i] = swapped[src[i]];
    }
    lcd.setAddrWindow(0, y0, render::kWidth, kBand);
    lcd.writePixelsDMA(dst, render::kWidth * kBand, false);  // already in panel order
    cur ^= 1;
    sent += kBand;
  }
  lcd.endWrite();
  pushedOnce = true;
  return sent;
}

void displayBacklight(uint8_t level) { lcd.setBrightness(level); }

bool touchRead(int& x, int& y) {
  if (digitalRead(pins::kTouchIrq) != LOW) return false;
  int32_t tx, ty;
  if (!lcd.getTouch(&tx, &ty)) return false;
  x = tx, y = ty;
  return true;
}

void touchRaw(int& x, int& y, int& z, bool& irq) {
  irq = digitalRead(pins::kTouchIrq) == LOW;
  lgfx::touch_point_t tp;
  if (lcd.getTouchRaw(&tp, 1)) {
    x = tp.x, y = tp.y, z = tp.size;
  } else {
    x = y = z = 0;
  }
}

}  // namespace board
