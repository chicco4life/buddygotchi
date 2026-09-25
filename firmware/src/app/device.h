// The device core: message dispatch, the debug channel, inputs and what's
// on screen (plan/PROTOCOL.md, plan/VERIFICATION.md §3). Pure C++: the board
// and the simulator run the same code behind a small Hal. F1 has the debug
// channel and inputs; F3 adds the behaviour state machine.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/clock.h"
#include "app/gesture.h"
#include "render/canvas.h"

namespace app {

enum class Link : uint8_t { kNone, kUsb, kBle };

// Where replies and device → Mac messages go.
struct Out {
  virtual ~Out() = default;
  virtual void write(const char* s, size_t n) = 0;
};

// What the core needs from the platform. Defaults suit the simulator.
struct Hal {
  virtual ~Hal() = default;
  virtual uint32_t realMs() = 0;
  virtual bool bootDown() { return false; }
  // A physical touch, in screen coordinates. False when nothing's pressed.
  virtual bool touch(int& x, int& y) {
    (void)x, (void)y;
    return false;
  }
  virtual void touchRaw(int& x, int& y, int& z, bool& irq) { x = y = z = 0, irq = false; }
  virtual void setLed(uint32_t rgb) { (void)rgb; }
  virtual void setBacklight(uint8_t level) { (void)level; }
  virtual uint32_t heapFree() { return 0; }
  virtual uint32_t heapMin() { return 0; }
  virtual uint32_t fps() { return 0; }
  virtual uint32_t batteryMv() { return 0; }
  virtual bool ampOn() { return false; }
  virtual const char* fwVersion() = 0;
  virtual const char* gitSha() = 0;
};

enum class Screen : uint8_t { kFace, kNeedsYou, kThreads, kStats, kNoApp, kPattern };
const char* screenName(Screen s);

class Device {
 public:
  // `pixels` is the kWidth × kHeight canvas buffer, allocated by the caller.
  Device(Hal& hal, uint8_t* pixels, bool frozenClock);

  void setOut(Link link, Out* out) { outs_[int(link)] = out; }

  // One message line. Replies go back on the link it came in on.
  void handleLine(const char* line, size_t n, Link from);
  // Reads inputs, advances state, and redraws the canvas if needed.
  void tick();
  // True once after each redraw.
  bool takeFrame() {
    bool f = frame_;
    frame_ = false;
    return f;
  }

  render::Canvas& canvas() { return canvas_; }
  uint32_t now() const { return clock_.now(hal_.realMs()); }
  Screen screen() const { return screen_; }

 private:
  struct LastInput {
    const char* k = nullptr;
    uint32_t at = 0;
    int x = -1, y = -1;
  };

  void reply(Link link, const char* text, size_t n);
  void emit(const char* k);  // an `input` message to the Mac
  void render();
  void sendPing(Link to);
  void sendState(Link to);
  void sendShot(Link to);
  void setScreen(Screen s);

  Hal& hal_;
  render::Canvas canvas_;
  Clock clock_;
  Rng rng_;
  ButtonGesture boot_;
  Out* outs_[3] = {nullptr, nullptr, nullptr};
  Link link_ = Link::kNone;  // the link the Mac last spoke on

  Screen screen_ = Screen::kFace;
  char base_[12] = "idle";
  bool dirty_ = true;
  bool frame_ = false;

  // Injected input, held until the clock passes `until`.
  bool injPress_ = false;
  uint32_t injPressUntil_ = 0;
  bool injTouch_ = false;
  uint32_t injTouchUntil_ = 0;
  int injX_ = 0, injY_ = 0;
  bool touchDown_ = false;

  LastInput last_;
  uint32_t led_ = 0;
  uint8_t backlight_ = 255;
};

}  // namespace app
