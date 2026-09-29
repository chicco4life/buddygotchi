// The microSD card (plan/DEVICE.md §2, plan/VOICE.md §8): mounted on the
// second hardware SPI bus at boot, with the voice pack Boop says its takes
// from. With no card, or no pack on it, Boop has no voice.
#pragma once
#include <cstddef>
#include <cstdint>

namespace board {

// Mounts the card and opens /boop/voice.bin for voice::openPack. False
// when there's no card or no pack; `cardState` says which.
bool cardBegin();
// `ok`, `no card`, `no pack` or `copying`, for dbg.ping.
const char* cardState();

// A new pack copied on over USB (dbg.card): /boop/voice.tmp, begun afresh
// or kept, appended to, then checked and renamed over the pack, which
// reopens (app::Hal's packBegin, packAppend and packEnd).
bool packBegin(bool keep, uint32_t& have, const char*& why);
bool packAppend(const uint8_t* d, size_t n, uint32_t& have);
bool packEnd(uint32_t size, uint32_t crc, const char*& why);

}  // namespace board
