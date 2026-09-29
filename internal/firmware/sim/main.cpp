// boop-sim: the device core on the Mac (plan/VERIFICATION.md §2, §4). It
// behaves like the board on USB: protocol and dbg.* lines on stdin, replies
// on stdout. `boopctl sim` drives it with the same scenario runner as the
// board, so a device screenshot and a simulator screenshot come from the
// same messages. The clock starts frozen at 0.
#ifndef PIO_UNIT_TESTING
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/stat.h>
#include <vector>

#include "../pack_file.h"
#include "app/codec.h"
#include "app/device.h"
#include "app/line_reader.h"

namespace {

struct SimHal : app::Hal {
  uint32_t realMs() override {
    using namespace std::chrono;
    return uint32_t(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
  }
  const char* cardState() override { return card; }
  const char* fwVersion() override { return "sim"; }
  const char* card = "no pack";

  // A card, with BOOP_SIM_CARD naming a folder for it: a pack copied on
  // with dbg.card goes to <folder>/boop/voice.bin, as on the board, and
  // is played from there.
  std::string dir = std::getenv("BOOP_SIM_CARD") ? std::getenv("BOOP_SIM_CARD") : "";
  packfile::FileSource pack, copy;
  std::string path(const char* name) const { return dir + "/boop/" + name; }
  bool openCardPack() {
    if (pack.f) std::fclose(pack.f), pack.f = nullptr;
    pack.f = std::fopen(path("voice.bin").c_str(), "rb");
    return pack.f && voice::openPack(&pack);
  }
  bool packBegin(bool keep, uint32_t& have, const char*& why) override {
    have = 0;
    if (dir.empty()) return why = "no card", false;
    ::mkdir(dir.c_str(), 0755), ::mkdir((dir + "/boop").c_str(), 0755);
    if (copy.f) std::fclose(copy.f);
    copy.f = std::fopen(path("voice.tmp").c_str(), keep ? "ab" : "wb");
    if (!copy.f) return why = "can't open /boop/voice.tmp", false;
    have = uint32_t(std::ftell(copy.f));
    return true;
  }
  bool packAppend(const uint8_t* d, size_t n, uint32_t& have) override {
    if (!copy.f) return have = 0, false;
    bool ok = !n || std::fwrite(d, 1, n, copy.f) == n;
    std::fflush(copy.f);
    have = uint32_t(std::ftell(copy.f));
    return ok;
  }
  bool packEnd(uint32_t size, uint32_t crc, const char*& why) override {
    if (!copy.f) return why = "no copy begun", false;
    std::fclose(copy.f), copy.f = nullptr;
    std::FILE* f = std::fopen(path("voice.tmp").c_str(), "rb");
    uint8_t buf[4096];
    uint32_t got = 0, sum = 0;
    for (size_t n; f && (n = std::fread(buf, 1, sizeof(buf), f)) > 0; got += uint32_t(n)) sum = app::crc32(buf, n, sum);
    if (f) std::fclose(f);
    if (got != size || sum != crc) return why = got != size ? "wrong size" : "wrong crc", false;
    voice::closePack();
    card = "no pack";
    if (std::rename(path("voice.tmp").c_str(), path("voice.bin").c_str()) || !openCardPack())
      return why = "can't swap it in", false;
    card = "ok";
    return true;
  }
  const char* gitSha() override { return "sim"; }
};

struct StdOut : app::Out {
  void write(const char* s, size_t n) override { std::fwrite(s, 1, n, stdout); }
};

}  // namespace

int main() {
  SimHal hal;
  // The voice pack, as on the board's card: the card folder's, with
  // BOOP_SIM_CARD, else .build/voice/voice.bin.
  if (hal.dir.empty() ? packfile::open() : hal.openCardPack()) hal.card = "ok";
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
