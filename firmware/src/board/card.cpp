#include "board/card.h"

#include <Arduino.h>
#include <FS.h>
#include <SD.h>
#include <SPI.h>

#include "app/codec.h"
#include "board/audio.h"
#include "board/pins.h"
#include "voice/player.h"

namespace board {

namespace {

// The card's SPI clock: the probe of 2026-09-29 read about 900 KB/s at
// 10 MHz, eighty times what a line needs (plan/evidence/2026-09-29-voice-sd).
constexpr uint32_t kCardHz = 10000000;
constexpr const char* kPackPath = "/boop/voice.bin";
constexpr const char* kCopyPath = "/boop/voice.tmp";

SPIClass cardSpi(VSPI);
const char* state = "no card";

// The pack's bytes from one open file: one for lookups on the main loop,
// another for the audio task, since a File isn't shared between tasks.
struct CardSource : voice::Source {
  File f;
  bool read(uint32_t at, void* buf, uint32_t n) override {
    return f && f.seek(at) && f.read(static_cast<uint8_t*>(buf), n) == n;
  }
};
CardSource lookups, samples;
bool mounted = false;
File copy;  // the pack being copied on

bool mount() {
  if (!mounted) mounted = SD.begin(pins::kCardCs, cardSpi, kCardHz, "/sd", 4);
  return mounted;
}

bool openPack() {
  lookups.f = SD.open(kPackPath);
  samples.f = SD.open(kPackPath);
  if (!lookups.f || !samples.f || !voice::openPack(&lookups, &samples)) return false;
  state = "ok";
  return true;
}

}  // namespace

bool cardBegin() {
  cardSpi.begin(pins::kCardSclk, pins::kCardMiso, pins::kCardMosi, pins::kCardCs);
  if (!mount()) return false;
  state = "no pack";
  return openPack();
}

bool packBegin(bool keep, uint32_t& have, const char*& why) {
  have = 0;
  if (copy) copy.close();
  if (!mount()) {
    why = "no card";
    return false;
  }
  SD.mkdir("/boop");
  if (!keep) SD.remove(kCopyPath);
  copy = SD.open(kCopyPath, FILE_APPEND);
  if (!copy) {
    why = "can't open /boop/voice.tmp";
    return false;
  }
  have = copy.size();
  return true;
}

bool packAppend(const uint8_t* d, size_t n, uint32_t& have) {
  if (!copy) {
    have = 0;
    return false;
  }
  bool ok = !n || copy.write(d, n) == n;
  have = copy.size();
  return ok;
}

bool packEnd(uint32_t size, uint32_t crc, const char*& why) {
  if (!copy) {
    why = "no copy begun";
    return false;
  }
  copy.close();
  // Read it all back: what the card holds, not what was sent.
  File f = SD.open(kCopyPath);
  static uint8_t buf[1024];
  uint32_t got = 0, sum = 0;
  for (size_t n; f && (n = f.read(buf, sizeof(buf))) > 0; got += n) sum = app::crc32(buf, n, sum);
  if (f) f.close();
  if (got != size || sum != crc) {
    why = got != size ? "wrong size" : "wrong crc";
    return false;
  }
  // Swap it in: nothing plays while the old pack closes.
  audioHush();
  delay(60);
  voice::closePack();
  lookups.f.close();
  samples.f.close();
  SD.remove(kPackPath);
  state = "no pack";
  if (!SD.rename(kCopyPath, kPackPath) || !openPack()) {
    why = "can't swap it in";
    return false;
  }
  return true;
}

const char* cardState() { return state; }

}  // namespace board
