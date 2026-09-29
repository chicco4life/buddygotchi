// The microSD card (plan/DEVICE.md §2, plan/VOICE.md §8): mounted on the
// second hardware SPI bus at boot, with the voice pack Boop says its takes
// from. With no card, or no pack on it, Boop has no voice.
#pragma once

namespace board {

// Mounts the card and opens /boop/voice.bin for voice::openPack. False
// when there's no card or no pack; `cardState` says which.
bool cardBegin();
// `ok`, `no card` or `no pack`, for dbg.ping.
const char* cardState();

}  // namespace board
