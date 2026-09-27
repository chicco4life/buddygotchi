#include "board/audio.h"

#include <Arduino.h>
#include <driver/dac_continuous.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

#include "board/pins.h"

namespace board {

namespace {

// Four 1 KB DMA buffers; the driver widens each sample to 16 bits, so each
// holds 512 samples (23 ms). The task writes one full buffer at a time and
// never lets the DMA run dry: silence when there's nothing to say. If the
// DMA ever finishes its queue, the synchronous driver stops handing buffers
// back (seen on the board, 2026-09-26), so an underrun must not happen.
constexpr size_t kDmaBufs = 4;
constexpr size_t kDmaBytes = 1024;
constexpr size_t kChunk = kDmaBytes / 2;
constexpr int kWriteTimeoutMs = 200;

enum class Kind : uint8_t { kSay, kCue, kHush };
struct Cmd {
  Kind kind;
  voice::Line line;
  voice::Cue cue;
  uint8_t vol;
};

dac_continuous_handle_t dac = nullptr;
QueueHandle_t queue = nullptr;
portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;
app::AudioOut stats;  // guarded by `lock`
voice::Player player;
uint8_t chunk[kChunk];

// The line being played, for its timeline. Writes return at the DMA's
// pace, so the time between the write before the line and the write that
// finished it is how long the DAC took to play those chunks.
struct Current {
  bool line = false;
  int syl = 0;
  bool word = false;
  uint32_t planMs = 0;
  uint32_t samples = 0;  // line samples rendered
  uint32_t chunks = 0;   // chunks they span
  int64_t startUs = 0;
};
Current cur;
int64_t lastWriteUs = 0;
int drain = 0;  // chunks left before the amp goes off: what's queued has to play first

template <typename F>
void locked(F f) {
  portENTER_CRITICAL(&lock);
  f();
  portEXIT_CRITICAL(&lock);
}

void finish(bool cut) {
  if (!cur.line) return;
  uint32_t wall = 0;
  if (cur.chunks) {  // the DAC's pace, over the line's own samples
    int64_t us = (lastWriteUs - cur.startUs) * int64_t(cur.samples) / int64_t(cur.chunks * kChunk);
    wall = uint32_t(us / 1000);
  }
  locked([&] {
    ++stats.lines;
    stats.syl = cur.syl;
    stats.word = cur.word;
    stats.planMs = cur.planMs;
    stats.outMs = cur.samples * 1000 / voice::kOutRate;
    stats.wallMs = wall;
    stats.cut = cut;
  });
  cur = Current{};
}

void apply(const Cmd& c) {
  if (cur.line) finish(true);  // anything new replaces a line
  switch (c.kind) {
    case Kind::kSay:
      player.start(c.line);
      if (player.playing()) {
        cur.line = true;
        cur.syl = c.line.n;
        cur.word = c.line.word >= 0;
        cur.planMs = voice::lineSamples(c.line) * 1000 / voice::kOutRate;
        cur.startUs = lastWriteUs;
      }
      break;
    case Kind::kCue: player.cue(c.cue, c.vol); break;
    case Kind::kHush: player.stop(); break;
  }
  if (player.playing()) {
    digitalWrite(pins::kAmpEnable, LOW);  // amp on (active low)
    drain = 0;
    locked([] { stats.playing = true; });
  } else if (drain == 0) {
    drain = int(kDmaBufs) + 1;  // hushed: let the queue play out, then the amp goes off
  }
}

void task(void*) {
  Cmd c;
  for (;;) {
    while (xQueueReceive(queue, &c, 0) == pdTRUE) apply(c);
    bool was = player.playing();
    size_t made = player.render(chunk, kChunk);
    if (dac_continuous_write(dac, chunk, kChunk, nullptr, kWriteTimeoutMs) != ESP_OK) {
      // Wedged anyway: restart the DAC so the next line can play.
      dac_continuous_disable(dac);
      dac_continuous_enable(dac);
      locked([] { ++stats.errors; });
    }
    lastWriteUs = esp_timer_get_time();
    if (cur.line && made) cur.samples += made, ++cur.chunks;
    if (was && !player.playing()) {
      finish(false);
      drain = int(kDmaBufs) + 1;
    }
    if (drain > 0 && --drain == 0 && !player.playing()) {
      digitalWrite(pins::kAmpEnable, HIGH);
      locked([] { stats.playing = false; });
    }
  }
}

void send(const Cmd& c) {
  if (!queue) return;
  if (xQueueSend(queue, &c, 0) != pdTRUE) {  // full: the newest wins
    Cmd old;
    xQueueReceive(queue, &old, 0);
    xQueueSend(queue, &c, 0);
  }
}

}  // namespace

bool audioBegin() {
  dac_continuous_config_t cfg = {};
  static_assert(pins::kDac == 26, "DAC_CHANNEL_MASK_CH1 is GPIO26 (DEVICE.md §2)");
  cfg.chan_mask = DAC_CHANNEL_MASK_CH1;
  cfg.desc_num = kDmaBufs;
  cfg.buf_size = kDmaBytes;
  cfg.freq_hz = voice::kOutRate;
  cfg.offset = 0;
  cfg.clk_src = DAC_DIGI_CLK_SRC_DEFAULT;
  cfg.chan_mode = DAC_CHANNEL_MODE_SIMUL;
  if (dac_continuous_new_channels(&cfg, &dac) != ESP_OK) return false;
  if (dac_continuous_enable(dac) != ESP_OK) return false;
  queue = xQueueCreate(2, sizeof(Cmd));
  if (!queue) return false;
  // Above Bluetooth's host task, so the DMA never runs dry.
  if (xTaskCreatePinnedToCore(task, "voice", 3072, nullptr, configMAX_PRIORITIES - 3, nullptr, 0) != pdPASS)
    return false;
  stats.ready = true;
  return true;
}

void audioSay(const voice::Line& l) {
  Cmd c{Kind::kSay, l, voice::Cue::kNone, 0};
  send(c);
}

void audioCue(voice::Cue cue, uint8_t vol) {
  Cmd c{Kind::kCue, voice::Line{}, cue, vol};
  send(c);
}

void audioHush() {
  Cmd c{Kind::kHush, voice::Line{}, voice::Cue::kNone, 0};
  send(c);
}

app::AudioOut audioOut() {
  app::AudioOut a;
  locked([&] { a = stats; });
  return a;
}

}  // namespace board
