// Sound on the board (plan/DEVICE.md §4, plan/VOICE.md §8, §10): a task on
// core 0 renders the voice player, mixes the sound effects in, and feeds
// ESP-IDF's continuous DAC on GPIO26 at 22.05 kHz, turning the amp on only
// while something plays. The main loop hands it lines and effects
// through a small queue, so a slow frame never stutters the sound.
#pragma once
#include "app/device.h"

namespace board {

// Starts the task and allocates the DAC's DMA buffers (about 4 KB).
bool audioBegin();
void audioSay(const voice::Line& l);
void audioHush();
void audioEffect(const voice::Effect& e);
void audioStopEffects();
app::AudioOut audioOut();

}  // namespace board
