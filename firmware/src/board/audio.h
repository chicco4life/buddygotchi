// Sound on the board (plan/DEVICE.md §4, plan/VOICE.md §8): a task on core
// 0 renders the voice player into ESP-IDF's continuous DAC on GPIO26 at
// 22.05 kHz, and turns the amp on only while something plays. The main
// loop hands it lines and cues through a small queue, so a slow frame
// never stutters the voice.
#pragma once
#include "app/device.h"

namespace board {

// Starts the task and allocates the DAC's DMA buffers (about 4 KB).
bool audioBegin();
void audioSay(const voice::Line& l);
void audioCue(voice::Cue c, uint8_t vol);
void audioHush();
app::AudioOut audioOut();

}  // namespace board
