#include "board/card.h"

#include <Arduino.h>
#include <FS.h>
#include <SD.h>
#include <SPI.h>

#include "board/pins.h"
#include "voice/player.h"

namespace board {

namespace {

// The card's SPI clock: the probe of 2026-09-29 read about 900 KB/s at
// 10 MHz, eighty times what a line needs (plan/evidence/2026-09-29-voice-sd).
constexpr uint32_t kCardHz = 10000000;
constexpr const char* kPackPath = "/boop/voice.bin";

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

}  // namespace

bool cardBegin() {
  cardSpi.begin(pins::kCardSclk, pins::kCardMiso, pins::kCardMosi, pins::kCardCs);
  if (!SD.begin(pins::kCardCs, cardSpi, kCardHz, "/sd", 3)) return false;
  lookups.f = SD.open(kPackPath);
  samples.f = SD.open(kPackPath);
  state = "no pack";
  if (!lookups.f || !samples.f || !voice::openPack(&lookups, &samples)) return false;
  state = "ok";
  return true;
}

const char* cardState() { return state; }

}  // namespace board
