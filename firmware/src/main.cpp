// Board entry point: allocate the canvas first, bring up the screen, then
// run the device core with USB serial as its link (plan/DEVICE.md §6–7).
#include <Arduino.h>
#include <esp_heap_caps.h>

#include "app/device.h"
#include "app/line_reader.h"
#include "board/board_hal.h"
#include "board/display.h"
#include "board/pins.h"

namespace {

struct SerialOut : app::Out {
  void write(const char* s, size_t n) override { Serial.write(reinterpret_cast<const uint8_t*>(s), n); }
};

board::BoardHal hal;
SerialOut usbOut;
app::LineReader usbLine;
app::Device* device = nullptr;

uint32_t frames = 0;
uint32_t fpsSince = 0;

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
  static app::Device dev(hal, pixels, /*frozenClock=*/false);
  device = &dev;
  device->setOut(app::Link::kUsb, &usbOut);
  fpsSince = millis();
}

void loop() {
  // One message per tick, so a reply always reflects every earlier message.
  bool busy = false;
  while (Serial.available() > 0) {
    if (usbLine.feed(char(Serial.read()))) {
      device->handleLine(usbLine.line(), usbLine.length(), app::Link::kUsb);
      busy = true;
      break;
    }
  }
  device->tick();
  if (device->takeFrame()) {
    board::displayPush(device->canvas());
    ++frames;
  }
  uint32_t now = millis();
  if (now - fpsSince >= 1000) {
    hal.setFps(frames * 1000 / (now - fpsSince));
    frames = 0;
    fpsSince = now;
  }
  if (!busy) delay(1);
}
