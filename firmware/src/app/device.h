// Boop on LinkKit: the app the kit calls (linkkit/device/src/linkkit/kit.h).
// It reads Boop's `state` and `do` args (plan/PROTOCOL.md), says when a
// call may play and when it rests or ends, recognises gestures, plays
// the voice and draws. What Boop does is decided by Behaviour. Pure C++:
// the board and the simulator run the same code behind a small Hal.
#pragma once
#include <cstddef>
#include <cstdint>

#include "app/behaviour.h"
#include "app/effect_track.h"
#include "app/gesture.h"
#include "app/touch_cal.h"
#include "linkkit/kit.h"
#include "render/anim.h"
#include "render/canvas.h"
#include "render/screens.h"
#include "render/sign.h"
#include "voice/effects.h"
#include "voice/player.h"

namespace app {

// Boop's names on the wire (PROTOCOL.md §2): hello.app, the Bluetooth name
// Boop-XXXX, and the device id b00p-xxxx.
constexpr const char* kAppName = "boop";
constexpr const char* kBleNamePrefix = "Boop";
constexpr const char* kIdPrefix = "b00p";
// The permanent ID in `hello` (PROTOCOL.md §4) where there's no Bluetooth
// MAC to take it from: the simulator and the tests.
constexpr const char* kDefaultDeviceId = "b00p-0000";

// What the sound output did (dbg.state `audio.out`): lines finished, and
// the last line's timeline as planned, as rendered and as the DAC took it.
struct AudioOut {
  bool ready = false;   // there's a DAC and it started
  bool playing = false;
  uint32_t lines = 0;
  int take = -1;        // the last line's first take (voice/player.h)
  uint32_t planMs = 0;  // the line's length
  uint32_t outMs = 0;   // samples rendered, at 22.05 kHz
  uint32_t wallMs = 0;  // time the DAC took to play them; 0 where there's no DAC
  bool cut = false;     // stopped early (hushed or replaced)
  uint32_t errors = 0;  // DAC writes that timed out
};

// What Boop needs from the platform, on top of the kit's. Defaults suit
// the simulator.
struct Hal : linkkit::Platform {
  const char* deviceId() override { return kDefaultDeviceId; }
  virtual bool bootDown() { return false; }
  // A physical touch, in screen coordinates. False when nothing's pressed.
  virtual bool touch(int& x, int& y) {
    (void)x, (void)y;
    return false;
  }
  virtual void touchRaw(int& x, int& y, int& z, bool& irq) { x = y = z = 0, irq = false; }
  // Touch calibration: the board applies it to touches and keeps it in NVS.
  virtual void setTouchCal(const TouchCal& c) { (void)c; }
  virtual TouchCal touchCal() { return {}; }
  virtual void setLed(uint32_t rgb) { (void)rgb; }
  virtual void setBacklight(uint8_t level) { (void)level; }
  virtual uint32_t heapFree() { return 0; }
  virtual uint32_t heapMin() { return 0; }
  virtual bool ampOn() { return false; }
  // Sound (VOICE.md §8). The board plays on the DAC; the default drops it.
  virtual void say(const voice::Line& l) { (void)l; }
  virtual void hush() {}
  // The face's sound effects (VOICE.md §10): one to play now, and stopping
  // every one playing.
  virtual void effect(const voice::Effect& e) { (void)e; }
  virtual void stopEffects() {}
  virtual AudioOut audioOut() { return {}; }
  // The microSD card that holds the voice pack, for dbg.ping's `card`
  // (PROTOCOL.md §5, VOICE.md §8); the simulator's is a file.
  virtual const char* cardState() { return "none"; }
  // Copying a new voice pack onto the card over USB (`dbg.card`, PROTOCOL.md
  // §5): a file begun afresh, or kept to go on where an earlier copy
  // stopped, then appended to, then checked against its size and CRC-32
  // and swapped in for the pack, which reopens. `have` is how many bytes
  // it holds. With no card they fail, and `why` says so.
  virtual bool packBegin(bool keep, uint32_t& have, const char*& why) {
    (void)keep, have = 0, why = "no card";
    return false;
  }
  virtual bool packAppend(const uint8_t* d, size_t n, uint32_t& have) {
    (void)d, (void)n, have = 0;
    return false;
  }
  virtual bool packEnd(uint32_t size, uint32_t crc, const char*& why) {
    (void)size, (void)crc, why = "no card";
    return false;
  }
  virtual const char* gitSha() = 0;
};

class Device : public linkkit::App {
 public:
  // A panel touch ends after this long without contact, in real ms.
  static constexpr uint32_t kTouchReleaseMs = 50;
  // A reaction rests this long after its line and bubble (PROTOCOL.md §3):
  // the pause the Mac used to leave between one reaction's bubble and the
  // next reaction or a rule's one-shot (its old MomentSchedule.linkSlackMs).
  static constexpr uint32_t kReactGapMs = 500;

  // `pixels` is the kWidth × kHeight canvas buffer, allocated by the
  // caller. A linkkit::Kit made with this app then drives it.
  Device(Hal& hal, uint8_t* pixels);

  // True once after each redraw.
  bool takeFrame() {
    bool f = frame_;
    frame_ = false;
    return f;
  }
  // The board drew and pushed a frame, taking this many microseconds for
  // each (dbg.ping `fps`, `draw_us`, `push_us`).
  void noteFrame(uint32_t drawUs, uint32_t pushUs) { drawUs_ = drawUs, pushUs_ = pushUs, ++frames_; }
  render::Canvas& canvas() { return canvas_; }

  // linkkit::App
  const char* name() const override { return kAppName; }
  int does(const char* const*& names) const override;
  void hello(JsonObject extra) override;
  void begin() override;
  void onState(JsonObjectConst state, uint32_t t) override;
  const char* refuse(const linkkit::Call& c, uint32_t t) override;
  void onDo(const linkkit::Call& c, uint32_t t) override;
  void advance(uint32_t t) override;
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override;
  void tick(uint32_t t) override;
  bool debug(const char* type, JsonObjectConst msg, linkkit::Link from) override;
  void ping(JsonObject reply) override;
  void state(JsonObject reply, uint32_t t) override;
  void reset() override;
  bool shot(linkkit::Shot& s, uint32_t t) override;

 private:
  struct LastInput {
    const char* k = nullptr;
    uint32_t at = 0;
    int x = -1, y = -1;
  };
  // The call refuse() last parsed, for onDo, which follows at once.
  struct Parsed {
    uint32_t key = 0;
    MomentIn in;
  };

  MomentIn parse(const linkkit::Call& c);
  void drain();  // Behaviour's ends, to the kit
  void input(const char* k, uint32_t t, int x = -1, int y = -1);
  void tapped(uint32_t t, bool injected);  // a tap, from BOOT or the panel
  void readInputs(uint32_t t);
  void render(uint32_t t);
  void hush();
  bool startLine(uint32_t t);
  void followSound(uint32_t t);
  Screen screenAt(uint32_t t) const { return pattern_ ? Screen::kPattern : b_.screen(t); }

  Hal& hal_;
  render::Canvas canvas_;
  Behaviour b_;
  ButtonGesture boot_;
  Parsed parsed_;
  // The holder's rest (PROTOCOL.md §3): a reaction rests kReactGapMs after
  // its line and bubble have played, restKey_ at restAt_; 0 when none is due.
  uint32_t restKey_ = 0;
  uint32_t restAt_ = 0;

  Screen screen_ = Screen::kFace;
  bool pattern_ = false;  // dbg.pattern until the next state
  int patternFill_ = -1;  // a solid dbg.pattern screen, or -1
  int targetX_ = -1, targetY_ = -1;  // a calibration target on dbg.pattern, or -1
  uint32_t drawnT_ = 0;   // the time of the last frame
  uint32_t drawnReal_ = 0;  // and the real time it was drawn
  // A hash of everything its face's pixels depend on (the SceneFrame's
  // bytes and whether the bubble was up), 0 for nothing: a copy of the
  // frame would hold 1.7 KB of the heap for good.
  uint64_t drawnKey_ = 0;
  // Or, while needs you's own design would show, the sign's pose instead.
  bool drawnSign_ = false;
  render::SignPose drawnPose_{};
  bool dirty_ = true;
  bool frame_ = false;
  // Frames pushed (noteFrame): counted over each real second into fps_.
  uint32_t frames_ = 0, fpsSinceReal_ = 0, fps_ = 0;
  uint32_t drawUs_ = 0, pushUs_ = 0;

  // Injected input, held until the clock passes `until`.
  bool injPress_ = false;
  uint32_t injPressUntil_ = 0;
  bool injTouch_ = false;
  uint32_t injTouchUntil_ = 0;
  int injX_ = 0, injY_ = 0;
  bool bootInjected_ = false;  // the BOOT press in progress is dbg.press's
  // The touch in progress, last in contact at real time touchSeenReal_.
  bool touchDown_ = false;
  bool touchInjected_ = false;  // it's dbg.touch's, not the panel's
  uint32_t touchSeenReal_ = 0;

  // A line is playing, and the moment (Behaviour::momentSeq) whose line
  // has started or been dropped: a newer one's starts when its bubble shows.
  bool saying_ = false;
  uint32_t saidSeq_ = 0;
  // The face's sound effects: its timeline, and the effects handed to the
  // Hal since boot, the last by its clip (dbg.state `audio.fx`).
  EffectTrack fx_;
  uint32_t fxSent_ = 0;
  int fxLast_ = -1;

  LastInput last_;
  uint32_t led_ = 0;
  uint8_t backlight_ = 255;
};

}  // namespace app
