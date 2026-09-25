// The device core: message dispatch, the debug channel, inputs and what's
// on screen (plan/PROTOCOL.md, plan/VERIFICATION.md §3). Pure C++: the board
// and the simulator run the same code behind a small Hal. What Boop does is
// decided by Behaviour; this class parses, recognises gestures and draws.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/behaviour.h"
#include "app/clock.h"
#include "app/gesture.h"
#include "render/anim.h"
#include "render/canvas.h"
#include "render/screens.h"
#include "voice/player.h"

namespace app {

enum class Link : uint8_t { kNone, kUsb, kBle };

// What the sound output did (dbg.state `audio.out`): lines finished, and
// the last line's timeline as planned, as rendered and as the DAC took it.
struct AudioOut {
  bool ready = false;   // there's a DAC and it started
  bool playing = false;
  uint32_t lines = 0;
  int syl = 0;          // syllables in the last line
  bool word = false;
  uint32_t planMs = 0;  // from `say`: beats × ms
  uint32_t outMs = 0;   // samples rendered, at 22.05 kHz
  uint32_t wallMs = 0;  // time the DAC took to play them; 0 where there's no DAC
  bool cut = false;     // stopped early (hushed or replaced)
  uint32_t errors = 0;  // DAC writes that timed out
};

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
  // The last frame's drawing and pushing time, in microseconds.
  virtual void frameUs(uint32_t& draw, uint32_t& push) { draw = push = 0; }
  virtual uint32_t batteryMv() { return 0; }
  virtual bool ampOn() { return false; }
  // Sound (VOICE.md §8). The board plays on the DAC; the default drops it.
  virtual void say(const voice::Line& l) { (void)l; }
  virtual void cue(voice::Cue c, uint8_t vol) { (void)c, (void)vol; }
  virtual void hush() {}
  virtual AudioOut audioOut() { return {}; }
  virtual bool usbPowered() { return true; }
  // The permanent ID in `status` (PROTOCOL.md §4).
  virtual const char* deviceId() { return "b00p-0000"; }
  // Bluetooth, for dbg.ping: "off", "adv" (advertising) or "conn".
  virtual const char* bleState() { return "off"; }
  virtual const char* bleName() { return ""; }
  virtual const char* fwVersion() = 0;
  virtual const char* gitSha() = 0;
};

class Device {
 public:
  // `pixels` is the kWidth × kHeight canvas buffer, allocated by the caller.
  Device(Hal& hal, uint8_t* pixels, bool frozenClock);

  void setOut(Link link, Out* out) { outs_[int(link)] = out; }

  // One message line. Replies go back on the link it came in on.
  void handleLine(const char* line, size_t n, Link from);
  // A Mac connected or disconnected over Bluetooth. USB has no connection
  // event: the Mac counts as connected when it first speaks, or speaks
  // again after kNoAppMs of silence.
  void connected(Link link);
  void disconnected(Link link);
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
  void input(const char* k, uint32_t t, int x = -1, int y = -1);
  void readInputs(uint32_t t);
  void render(uint32_t t);
  void sendPing(Link to);
  void sendStatus(Link to);
  void sendState(Link to);
  void sendShot(Link to);
  void reset();
  void parseState(const char* line, size_t n, uint32_t at);
  void hush();
  void followSound(uint32_t t);
  Screen screenAt(uint32_t t) const { return pattern_ ? Screen::kPattern : b_.screen(t); }

  Hal& hal_;
  render::Canvas canvas_;
  Clock clock_;
  Rng rng_;
  Behaviour b_;
  ButtonGesture boot_;
  Out* outs_[3] = {nullptr, nullptr, nullptr};
  Link link_ = Link::kNone;  // the link the Mac last spoke on
  uint32_t heardReal_ = 0;   // real time the Mac last spoke, for USB's "connect"
  uint32_t statusReal_ = 0;  // real time of the last status

  Screen screen_ = Screen::kFace;
  bool pattern_ = false;  // dbg.pattern until the next state
  // `state` and `moment` messages received since boot (dbg.state `rx`), so
  // the pipeline check can see exactly when the Mac's message arrived.
  uint32_t rxState_ = 0;
  uint32_t rxMoment_ = 0;
  int patternFill_ = -1;  // a solid dbg.pattern screen, or -1
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
  // The touch in progress.
  bool touchDown_ = false, touchHeld_ = false, touchStrip_ = false;
  uint32_t touchAt_ = 0;

  // The line playing (its moment's number), and the last sound cue heard.
  bool saying_ = false;
  uint32_t sayMoment_ = 0;
  const char* sfxSeen_ = nullptr;
  uint32_t sfxSeenAt_ = 0;

  LastInput last_;
  uint32_t led_ = 0;
  uint8_t backlight_ = 255;
};

}  // namespace app
