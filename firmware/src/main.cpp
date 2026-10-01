// Board entry point: allocate the canvas first, bring up the screen and
// Bluetooth, then run Boop on LinkKit with USB serial and BLE as its links
// (documentation/DEVICE.md §4).
#include <Arduino.h>
#include <esp_heap_caps.h>

#include "app/device.h"
#include "board/audio.h"
#include "board/board_hal.h"
#include "board/display.h"
#include "board/pins.h"
#include "linkkit/ble.h"
#include "linkkit/kit.h"
#include "linkkit/line_reader.h"

namespace {

struct SerialOut : linkkit::Out {
  void write(const char* s, size_t n) override { Serial.write(reinterpret_cast<const uint8_t*>(s), n); }
};

board::BoardHal hal;
SerialOut usbOut;
linkkit::LineReader usbLine;
linkkit::Ble ble;
app::Device* device = nullptr;
linkkit::Kit* kit = nullptr;

// Lines are handled for at most this long before the next frame is drawn.
constexpr uint32_t kLinesUs = 8000;

}  // namespace

void setup() {
  // The canvas comes first, while one contiguous 76.8 KB block is still free.
  const size_t canvasBytes = size_t(render::kWidth) * render::kHeight;
  auto* pixels = static_cast<uint8_t*>(heap_caps_malloc(canvasBytes, MALLOC_CAP_8BIT));

  Serial.setRxBufferSize(2048);
  Serial.begin(460800);  // the CH340 on macOS can't do 921600
  hal.begin();
  if (!pixels || !board::displayBegin()) {
    // Nothing to draw with: say so on USB and keep the backlight on.
    pinMode(pins::kBacklight, OUTPUT);
    digitalWrite(pins::kBacklight, HIGH);
    for (;;) {
      Serial.println("{\"t\":\"dbg.fatal\",\"why\":\"canvas or display init failed\"}");
      delay(2000);
    }
  }
  board::audioBegin();  // dbg.state audio.out.ready says whether it worked
  static app::Device dev(hal, pixels);
  static linkkit::Kit k(hal, dev, /*frozenClock=*/false);
  device = &dev;
  kit = &k;
  kit->setOut(linkkit::Link::kUsb, &usbOut);
  // Bluetooth after the canvas, so the canvas got its contiguous block.
  if (ble.begin(app::kBleNamePrefix, app::kIdPrefix)) kit->setOut(linkkit::Link::kBle, &ble);
  hal.setBle(&ble);
}

void loop() {
  // Every line waiting, then one frame. Drawing between lines (up to 31 ms a
  // frame) let a burst overflow the 2 KB receive buffers and lose lines. A
  // debug message ends the batch, since tests order it against ticks; each
  // reply still reflects every message before it.
  bool busy = false, debug = false;
  const uint32_t start = micros();
  for (bool more = true; more && !debug && micros() - start < kLinesUs;) {
    more = false;
    while (Serial.available() > 0) {
      if (!usbLine.feed(char(Serial.read()))) continue;
      debug = kit->handleLine(usbLine.line(), usbLine.length(), linkkit::Link::kUsb);
      busy = more = true;
      break;
    }
    if (!debug && ble.poll(*kit)) busy = more = true;
  }
  uint32_t t0 = micros();
  kit->tick();
  if (device->takeFrame()) {
    uint32_t t1 = micros();
    board::displayPush(device->canvas());
    device->noteFrame(t1 - t0, micros() - t1);
  }
  if (!busy) delay(1);
}
