// boop-sim: the device core on the Mac (plan/VERIFICATION.md §2, §4). It
// behaves like the board on USB: protocol and dbg.* lines on stdin, replies
// on stdout. `boopctl sim` drives it with the same scenario runner as the
// board, so a device screenshot and a simulator screenshot come from the
// same messages. The clock starts frozen at 0.
#ifndef PIO_UNIT_TESTING
#include <chrono>
#include <cstdio>
#include <vector>

#include "app/device.h"
#include "app/line_reader.h"

namespace {

struct SimHal : app::Hal {
  uint32_t realMs() override {
    using namespace std::chrono;
    return uint32_t(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
  }
  const char* fwVersion() override { return "sim"; }
  const char* gitSha() override { return "sim"; }
};

struct StdOut : app::Out {
  void write(const char* s, size_t n) override { std::fwrite(s, 1, n, stdout); }
};

}  // namespace

int main() {
  SimHal hal;
  StdOut out;
  std::vector<uint8_t> pixels(size_t(render::kWidth) * render::kHeight, 0);
  app::Device device(hal, pixels.data(), /*frozenClock=*/true);
  device.setOut(app::Link::kUsb, &out);
  device.tick();

  // Lines go through the board's own LineReader, so a line over its limit
  // (plan/PROTOCOL.md §2) is dropped here exactly as on USB.
  app::LineReader reader;
  for (int c; (c = std::getchar()) != EOF;) {
    if (!reader.feed(char(c))) continue;
    device.handleLine(reader.line(), reader.length(), app::Link::kUsb);
    device.tick();
    std::fflush(stdout);
  }
  return 0;
}
#endif
