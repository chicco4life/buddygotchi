// Sound on the board (plan/DEVICE.md §4, plan/VOICE.md §8, §10): a task on
// core 0 renders the voice player, mixes the sound effects in, and feeds
// ESP-IDF's continuous DAC on GPIO26 at 22.05 kHz, turning the amp on only
// while something plays. The main loop hands it lines and effects
// through a small queue, so a slow frame never stutters the sound.
#pragma once

namespace board {

// Starts the task and allocates the DAC's DMA buffers (about 4 KB).
// BoardHal's say, hush, effect, stopEffects and audioOut feed it.
bool audioBegin();

}  // namespace board
