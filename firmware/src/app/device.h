// The device core: message dispatch, the debug channel, inputs and what's
// on screen (plan/PROTOCOL.md, plan/VERIFICATION.md §3). Pure C++: the board
// and the simulator run the same code behind a small Hal. F2 keeps what the
// Mac last said and draws it; F3 adds the behaviour state machine.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/clock.h"
#include "app/gesture.h"
#include "render/anim.h"
#include "render/canvas.h"
#include "render/screens.h"

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
  // What the Mac last said (PROTOCOL.md §3).
  struct Model {
    char base[12] = "idle";
    bool attn = false;
    char agent[12] = "";
    char project[24] = "";
    int more = 0;
    uint32_t attnSince = 0;
    int busy = 0, idle = 0, wait = 0;
    int quiet = 0;
    bool focus = false;
    char name[16] = "";
    int level = 1, prog = 0, days = 0;
    render::Thread threads[8];
    int nThreads = 0;
    uint32_t lastState = 0;  // when the last `state` arrived
  };
  struct Moment {
    render::Anim anim = render::Anim::kNone;
    int size = 1;
    uint32_t at = 0, ms = 0;
    render::Mumble say;
    char word[24] = "";
  };
  // What the face is following: a moment, or a look from the state.
  struct Source {
    render::Anim anim = render::Anim::kNone;
    int size = 0;
    uint32_t at = 0;
    render::Look look = render::Look::kIdle;
    int rung = 0;
    bool operator==(const Source& o) const {
      return anim == o.anim && size == o.size && at == o.at && look == o.look && rung == o.rung;
    }
  };

  struct LastInput {
    const char* k = nullptr;
    uint32_t at = 0;
    int x = -1, y = -1;
  };

  void reply(Link link, const char* text, size_t n);
  void emit(const char* k);  // an `input` message to the Mac
  void render(uint32_t t);
  void sendPing(Link to);
  void sendState(Link to);
  void sendShot(Link to);
  void reset();
  // Moves the model to time t, starting blends at the exact moments that
  // time-based changes happen (a moment ends, the app goes quiet, a rung).
  void advance(uint32_t t);
  // After a message changed the model at t: blend if the face's source moved.
  void resync(uint32_t t);
  bool noApp(uint32_t t) const;
  int rung(uint32_t t) const;
  Source sourceAt(uint32_t t) const;
  render::Pose sourcePose(const Source& s, uint32_t t) const;
  render::Pose poseAt(uint32_t t) const { return blend_.apply(t, sourcePose(src_, t)); }
  Screen screenAt(uint32_t t) const;
  render::Strip strip(uint32_t t) const;

  Hal& hal_;
  render::Canvas canvas_;
  Clock clock_;
  Rng rng_;
  ButtonGesture boot_;
  Out* outs_[3] = {nullptr, nullptr, nullptr};
  Link link_ = Link::kNone;  // the link the Mac last spoke on

  Screen screen_ = Screen::kFace;
  bool pattern_ = false;  // dbg.pattern until the next state
  int patternFill_ = -1;  // a solid dbg.pattern screen, or -1
  Screen userScreen_ = Screen::kFace;  // face, threads or stats (strip taps)
  Model model_;
  Moment moment_;
  Source src_;
  render::Blend blend_;
  uint32_t modelT_ = 0;   // the time the model was last advanced to
  uint32_t drawnT_ = 0;   // the time of the last frame
  bool drawnMoving_ = false;  // it was mid-motion, so the next time step redraws
  bool dirty_ = true;
  bool frame_ = false;

  // Injected input, held until the clock passes `until`.
  bool injPress_ = false;
  uint32_t injPressUntil_ = 0;
  bool injTouch_ = false;
  uint32_t injTouchUntil_ = 0;
  int injX_ = 0, injY_ = 0;
  bool touchDown_ = false;
  uint32_t touchAt_ = 0;
  int touchX_ = 0, touchY_ = 0;

  LastInput last_;
  uint32_t led_ = 0;
  uint8_t backlight_ = 255;
};

}  // namespace app
