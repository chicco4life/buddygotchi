#include "app/device.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "app/codec.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/screens.h"

namespace app {

namespace {

constexpr uint32_t kDefaultPressMs = 100;

const char* linkName(Link l) {
  switch (l) {
    case Link::kUsb: return "usb";
    case Link::kBle: return "ble";
    default: return "none";
  }
}

bool parseHex(const char* s, uint32_t& out) {
  if (!s || s[0] != '#' || std::strlen(s) != 7) return false;
  unsigned v = 0;
  if (std::sscanf(s + 1, "%6x", &v) != 1) return false;
  out = v;
  return true;
}

void sinkToOut(void* ctx, const char* text, size_t n) { static_cast<Out*>(ctx)->write(text, n); }

}  // namespace

const char* screenName(Screen s) {
  switch (s) {
    case Screen::kFace: return "face";
    case Screen::kNeedsYou: return "needs_you";
    case Screen::kThreads: return "threads";
    case Screen::kStats: return "stats";
    case Screen::kNoApp: return "no_app";
    case Screen::kPattern: return "pattern";
  }
  return "face";
}

Device::Device(Hal& hal, uint8_t* pixels, bool frozenClock) : hal_(hal), canvas_(pixels) {
  clock_.start(frozenClock, hal_.realMs());
}

void Device::reply(Link link, const char* text, size_t n) {
  Out* out = outs_[int(link)];
  if (!out) return;
  out->write(text, n);
  out->write("\n", 1);
}

void Device::emit(const char* k) {
  char buf[48];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"input\",\"k\":\"%s\"}", k);
  reply(link_, buf, size_t(n));
}

void Device::setScreen(Screen s) {
  if (s != screen_) dirty_ = true;
  screen_ = s;
}

void Device::handleLine(const char* line, size_t n, Link from) {
  JsonDocument doc;
  if (deserializeJson(doc, line, n) != DeserializationError::Ok) return;
  const char* t = doc["t"];
  if (!t) return;
  bool debug = std::strncmp(t, "dbg.", 4) == 0;
  if (debug && from != Link::kUsb) return;  // the debug channel is USB only
  if (!debug) link_ = from;
  uint32_t real = hal_.realMs();

  if (!std::strcmp(t, "state")) {
    const char* base = doc["base"];
    if (base) std::snprintf(base_, sizeof(base_), "%s", base);
    setScreen(Screen::kFace);
  } else if (!std::strcmp(t, "dbg.ping")) {
    sendPing(from);
  } else if (!std::strcmp(t, "dbg.state")) {
    sendState(from);
  } else if (!std::strcmp(t, "dbg.shot")) {
    sendShot(from);
  } else if (!std::strcmp(t, "dbg.pattern")) {
    setScreen(Screen::kPattern);
    reply(from, "{\"t\":\"dbg.pattern\"}", 19);
  } else if (!std::strcmp(t, "dbg.clock")) {
    if (doc["freeze"].is<uint32_t>()) {
      uint32_t at = doc["freeze"];
      clock_.freeze(at);
      rng_.seed(at);
    } else if (doc["step"].is<uint32_t>()) {
      clock_.step(doc["step"].as<uint32_t>(), real);
    } else if (doc["run"].as<bool>()) {
      clock_.run(real);
    }
    char buf[64];
    int len = std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.clock\",\"now\":%lu,\"frozen\":%s}",
                            (unsigned long)now(), clock_.frozen() ? "true" : "false");
    reply(from, buf, size_t(len));
  } else if (!std::strcmp(t, "dbg.press")) {
    injPress_ = true;
    injPressUntil_ = now() + (doc["ms"] | kDefaultPressMs);
    reply(from, "{\"t\":\"dbg.press\"}", 17);
  } else if (!std::strcmp(t, "dbg.touch")) {
    injTouch_ = true;
    injX_ = doc["x"] | 0;
    injY_ = doc["y"] | 0;
    injTouchUntil_ = now() + (doc["ms"] | kDefaultPressMs);
    reply(from, "{\"t\":\"dbg.touch\"}", 17);
  } else if (!std::strcmp(t, "dbg.light")) {
    if (doc["bl"].is<int>()) {
      backlight_ = uint8_t(doc["bl"].as<int>());
      hal_.setBacklight(backlight_);
    }
    uint32_t rgb;
    if (parseHex(doc["led"], rgb)) {
      led_ = rgb;
      hal_.setLed(rgb);
    }
    reply(from, "{\"t\":\"dbg.light\"}", 17);
  }
}

void Device::tick() {
  uint32_t t = now();

  // BOOT: the physical button or an injected press.
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false;
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kTap:
      last_ = {"tap", t, -1, -1};
      emit("tap");
      break;
    case ButtonGesture::kHoldStart:
      last_ = {"talk_on", t, -1, -1};
      emit("talk_on");
      break;
    case ButtonGesture::kHoldEnd:
      last_ = {"talk_off", t, -1, -1};
      emit("talk_off");
      break;
    default:
      break;
  }

  // Touch: F1 records where; F3 turns it into gestures.
  if (injTouch_ && int32_t(t - injTouchUntil_) >= 0) injTouch_ = false;
  int x = 0, y = 0;
  bool touching = injTouch_ ? (x = injX_, y = injY_, true) : hal_.touch(x, y);
  if (touching && !touchDown_) last_ = {"touch", t, x, y};
  touchDown_ = touching;

  if (dirty_) render();
}

void Device::render() {
  switch (screen_) {
    case Screen::kPattern: render::drawPattern(canvas_); break;
    default: render::drawPlaceholderFace(canvas_); break;
  }
  dirty_ = false;
  frame_ = true;
}

void Device::sendPing(Link to) {
  JsonDocument d;
  d["t"] = "dbg.ping";
  d["fw"] = hal_.fwVersion();
  d["sha"] = hal_.gitSha();
  d["up"] = hal_.realMs();
  d["heap"] = hal_.heapFree();
  d["heap_min"] = hal_.heapMin();
  d["fps"] = hal_.fps();
  d["link"] = linkName(link_);
  char buf[256];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

void Device::sendState(Link to) {
  JsonDocument d;
  d["t"] = "dbg.state";
  d["screen"] = screenName(screen_);
  d["base"] = base_;
  d["attn"] = nullptr;
  d["rung"] = 0;
  d["moment"] = nullptr;
  d["quiet"] = 0;
  d["focus"] = false;
  char led[8];
  std::snprintf(led, sizeof(led), "#%06lX", (unsigned long)(led_ & 0xFFFFFF));
  d["led"] = led;
  d["audio"]["playing"] = false;
  d["audio"]["syllables"] = 0;
  if (last_.k) {
    JsonObject li = d["last_input"].to<JsonObject>();
    li["k"] = last_.k;
    li["at"] = last_.at;
    if (last_.x >= 0) {
      li["x"] = last_.x;
      li["y"] = last_.y;
    }
  } else {
    d["last_input"] = nullptr;
  }
  // Bring-up extras (F1): the clock and raw hardware readings.
  d["clock"]["now"] = now();
  d["clock"]["frozen"] = clock_.frozen();
  d["boot"] = boot_.down();
  int rx, ry, rz;
  bool irq;
  hal_.touchRaw(rx, ry, rz, irq);
  JsonObject touch = d["touch"].to<JsonObject>();
  touch["down"] = touchDown_;
  touch["irq"] = irq;
  JsonArray raw = touch["raw"].to<JsonArray>();
  raw.add(rx), raw.add(ry), raw.add(rz);
  d["bat"] = hal_.batteryMv();
  d["amp"] = hal_.ampOn();
  d["bl"] = backlight_;
  char buf[768];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

// Header line, then one base64 line: 256 little-endian RGB565 palette
// entries followed by one palette index per pixel, row by row.
void Device::sendShot(Link to) {
  Out* out = outs_[int(to)];
  if (!out) return;
  if (dirty_) render();
  uint8_t pal[512];
  for (int i = 0; i < 256; ++i) {
    uint16_t c = render::paletteAt(i);
    pal[2 * i] = uint8_t(c & 0xFF);
    pal[2 * i + 1] = uint8_t(c >> 8);
  }
  const size_t npx = size_t(render::kWidth) * render::kHeight;
  uint32_t crc = crc32(canvas_.pixels(), npx, crc32(pal, sizeof(pal)));
  char head[128];
  int n = std::snprintf(head, sizeof(head), "{\"t\":\"dbg.shot\",\"w\":%d,\"h\":%d,\"bytes\":%u,\"crc\":%lu}",
                        render::kWidth, render::kHeight, unsigned(sizeof(pal) + npx), (unsigned long)crc);
  reply(to, head, size_t(n));
  Base64Writer b64(sinkToOut, out);
  b64.write(pal, sizeof(pal));
  b64.write(canvas_.pixels(), npx);
  b64.finish();
  out->write("\n", 1);
}

}  // namespace app
