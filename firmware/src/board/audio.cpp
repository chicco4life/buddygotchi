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

// Effects neither replace nor hush a line: they mix under it.
enum class Kind : uint8_t { kSay, kHush, kEffect, kStopEffects };
struct Cmd {
  Kind kind;
  voice::Line line;
  voice::Effect effect;
};
// The amp stays on this many chunks (about a second) after the last sound:
// what's queued has to play first, and a working design's clicks come a
// few times a second, so it doesn't switch on and off between them.
constexpr int kAmpHold = 44;
// Deep enough for the busiest design's events between two passes of the
// main loop, and a line.
constexpr int kQueue = 8;

dac_continuous_handle_t dac = nullptr;
QueueHandle_t queue = nullptr;
portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;
app::AudioOut stats;  // guarded by `lock`
voice::Player player;
voice::Effects effects;
uint8_t chunk[kChunk];

// The line being played, for its timeline. Writes return at the DMA's
// pace, so the time between the write before the line and the write that
// finished it is how long the DAC took to play those chunks.
struct Current {
  bool line = false;
  int take = -1;
  uint32_t planMs = 0;
  uint32_t samples = 0;  // line samples rendered
  uint32_t chunks = 0;   // chunks they span
  int64_t startUs = 0;
};
Current cur;
int64_t lastWriteUs = 0;
int drain = 0;  // chunks left before the amp goes off (kAmpHold)

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
    stats.take = cur.take;
    stats.planMs = cur.planMs;
    stats.outMs = cur.samples * 1000 / voice::kOutRate;
    stats.wallMs = wall;
    stats.cut = cut;
  });
  cur = Current{};
}

void applyVoice(const Cmd& c) {
  if (cur.line) finish(true);  // anything new replaces a line
  switch (c.kind) {
    case Kind::kSay:
      player.start(c.line);
      if (player.playing()) {
        cur.line = true;
        cur.take = c.line.take;
        cur.planMs = voice::lineSamples(c.line) * 1000 / voice::kOutRate;
        cur.startUs = lastWriteUs;
      }
      break;
    case Kind::kHush: player.stop(); break;
    default: break;
  }
}

bool sounding() { return player.playing() || effects.playing(); }

void apply(const Cmd& c) {
  if (c.kind == Kind::kEffect || c.kind == Kind::kStopEffects) {
    if (c.kind == Kind::kEffect) effects.play(c.effect);
    else effects.stop();
  } else {
    applyVoice(c);
  }
  if (sounding()) {
    digitalWrite(pins::kAmpEnable, LOW);  // amp on (active low)
    drain = 0;
    locked([] { stats.playing = true; });
  } else if (drain == 0) {
    drain = kAmpHold;  // hushed: let the queue play out, then the amp goes off
  }
}

void task(void*) {
  Cmd c;
  for (;;) {
    while (xQueueReceive(queue, &c, 0) == pdTRUE) apply(c);
    bool was = player.playing();
    bool wasAny = sounding();
    bool speaking = player.playing();  // a line, which the effects go under
    size_t made = player.render(chunk, kChunk);
    effects.mix(chunk, kChunk, speaking);
    if (dac_continuous_write(dac, chunk, kChunk, nullptr, kWriteTimeoutMs) != ESP_OK) {
      // Wedged anyway: restart the DAC so the next line can play.
      dac_continuous_disable(dac);
      dac_continuous_enable(dac);
      locked([] { ++stats.errors; });
    }
    lastWriteUs = esp_timer_get_time();
    if (cur.line && made) cur.samples += made, ++cur.chunks;
    if (was && !player.playing()) finish(false);
    if (wasAny && !sounding()) drain = kAmpHold;
    if (drain > 0 && --drain == 0 && !sounding()) {
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
  queue = xQueueCreate(kQueue, sizeof(Cmd));
  if (!queue) return false;
  // Above Bluetooth's host task, so the DMA never runs dry. Its stack has
  // room for reading the card (FatFs and the SPI driver) as it plays.
  if (xTaskCreatePinnedToCore(task, "voice", 6144, nullptr, configMAX_PRIORITIES - 3, nullptr, 0) != pdPASS)
    return false;
  stats.ready = true;
  return true;
}

void audioSay(const voice::Line& l) {
  Cmd c{Kind::kSay, l, {}};
  send(c);
}

void audioHush() {
  Cmd c{Kind::kHush, voice::Line{}, {}};
  send(c);
}

void audioEffect(const voice::Effect& e) {
  Cmd c{Kind::kEffect, voice::Line{}, e};
  send(c);
}

void audioStopEffects() {
  Cmd c{Kind::kStopEffects, voice::Line{}, {}};
  send(c);
}

app::AudioOut audioOut() {
  app::AudioOut a;
  locked([&] { a = stats; });
  return a;
}

}  // namespace board
