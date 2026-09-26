// The behaviour state machine (plan/BEHAVIORS.md, plan/UX.md §3–4): what
// the Mac last said, the moment playing, idle life, the needs-you ladder,
// local reactions to inputs, and the light, backlight and sound cues they
// imply. Pure C++ and a function of the device clock: every time-based
// change happens at an exact millisecond, so a frozen clock gives the same
// frames on the board and in the simulator. Device owns the I/O.
#pragma once
#include <cstdint>

#include "app/clock.h"
#include "render/anim.h"
#include "render/screens.h"

namespace app {

enum class Screen : uint8_t { kFace, kNeedsYou, kThreads, kStats, kNoApp, kPattern };
const char* screenName(Screen s);

// What the Mac last said (PROTOCOL.md §3).
struct Model {
  char base[12] = "idle";
  bool attn = false;
  char agent[12] = "";
  char project[24] = "";
  int more = 0;
  int busy = 0, idle = 0, wait = 0;
  int energy = 100, pace = 100, pitch = 100;
  int quiet = 0;
  int vol = 6;
  bool night = false;
  char name[24] = "";  // the Mac clips it to 23 bytes on a character boundary
  int level = 1, prog = 0, days = 0;
  int hungry = 0;
  render::Thread threads[8];
  int nThreads = 0;
};

// A moment as it arrives (PROTOCOL.md §3).
struct MomentIn {
  render::Anim anim = render::Anim::kNone;
  int size = 1;
  int syllables = 0;  // 0: no mumble
  const char* word = nullptr;
  int at = -1;
  uint32_t ms = 120;  // per syllable
};

// Idle life: small things Boop does on its own (BEHAVIORS.md §2).
enum class Life : uint8_t { kNone, kBlink, kGlance, kBob, kPeek, kRumble };
const char* lifeName(Life l);

class Behaviour {
 public:
  // Timings (BEHAVIORS.md, UX.md). Proposed values are marked there.
  static constexpr uint32_t kNoAppMs = 30000;
  static constexpr uint32_t kRung2Ms = 45000;
  static constexpr uint32_t kRung3Ms = 120000;
  static constexpr uint32_t kUserScreenMs = 10000;  // threads and stats close
  static constexpr uint32_t kPulseMs = 400;         // one rung-3 light pulse
  static constexpr uint32_t kBubbleReadMs = 1200;   // the word stays up after the mumble
  static constexpr uint32_t kPressEaseMs = 60;      // the press squish

  void reset(uint32_t t, Rng& rng);

  // Messages from the Mac, at time t.
  void onState(const Model& m, uint32_t t, Rng& rng);
  // True when the moment carries a mumble that will play: not during needs
  // you or quiet.
  bool onMoment(const MomentIn& m, uint32_t t, Rng& rng);

  // Inputs, already recognised as gestures (UX.md §4).
  void pressDown(uint32_t t);  // visible feedback at once
  void pressUp(uint32_t t);
  void tap(uint32_t t, Rng& rng);  // BOOT or the face
  void talkOn(uint32_t t, Rng& rng);
  void talkOff(uint32_t t, Rng& rng);
  void stripTap(uint32_t t);    // cycles face → threads → stats; the no-app screen ignores it
  void contentTap(uint32_t t);  // a tap on threads or stats goes back to the face
  // dbg.light: holds the LED and backlight until the next state.
  void overrideLed(uint32_t rgb) { ledOverride_ = true, ledSet_ = rgb; }
  void overrideBacklight(uint8_t level) { blOverride_ = true, blSet_ = level; }

  // Moves to time t, handling every time-based change on the way at its
  // exact millisecond (a moment ends, a rung, idle life, timeouts).
  void advance(uint32_t t, Rng& rng);

  // Queries at t (after advance).
  Screen screen(uint32_t t) const;
  render::Pose pose(uint32_t t) const;
  bool moving(uint32_t t) const;
  int rung(uint32_t t) const;
  bool noApp(uint32_t t) const;
  uint32_t led(uint32_t t) const;
  uint8_t backlight(uint32_t t) const;
  render::Strip strip(uint32_t t) const;
  // The mumble in the bubble, or null.
  const render::Mumble* mumble(uint32_t t) const;
  // The moment showing: its anim (kNone for none) and ms left.
  render::Anim moment(uint32_t t, uint32_t& left) const;
  bool speaking(uint32_t t) const;
  int syllables() const { return moment_.say.syllables; }
  // Counts moments played, local ones included, so a line can tell it was replaced.
  uint32_t momentSeq() const { return momentSeq_; }
  Life life(uint32_t t) const;
  // What the face is following at t: the moment's anim ("cheer"), or the
  // look ("idle", "working", "asleep", "no_app", "needs_you").
  const char* faceName(uint32_t t) const;
  bool hushed() const { return model_.attn && hushed_; }
  const char* sfx(uint32_t& at) const {
    at = sfxAt_;
    return sfx_;
  }
  const Model& model() const { return model_; }

 private:
  struct Moment {
    render::Anim anim = render::Anim::kNone;
    int size = 1;
    int pace = 100;
    uint32_t at = 0, ms = 0;
    uint32_t speakMs = 0;  // the mouth moves this long
    uint32_t sylMs = 120;
    render::Mumble say;
    char word[24] = "";
    bool local = false;
  };
  // What the face is following: a moment, or a look from the state.
  struct Source {
    render::Anim anim = render::Anim::kNone;
    uint32_t at = 0;
    render::Look look = render::Look::kIdle;
    int rung = 0;
    bool operator==(const Source& o) const {
      return anim == o.anim && at == o.at && look == o.look && rung == o.rung;
    }
  };
  struct LifeEvent {
    Life kind = Life::kNone;
    uint32_t at = 0, ms = 0;
    int dx = 0, dy = 0;  // where a glance looks, permille
  };

  void play(render::Anim a, int size, uint32_t t, bool local);
  void sound(const char* k, uint32_t t);
  void resync(uint32_t t, Rng& rng);
  void startLife(uint32_t t, Rng& rng);
  uint32_t lifeGap(Rng& rng) const;
  bool momentOn(uint32_t t) const;
  Source sourceAt(uint32_t t) const;
  render::Pose basePose(const Source& s, uint32_t t) const;
  render::Pose sourcePose(const Source& s, uint32_t t) const;
  render::Pose blended(uint32_t t) const { return blend_.apply(t, sourcePose(src_, t)); }
  int rungAt(uint32_t t) const;

  Model model_;
  bool heard_ = false;       // a state arrived since reset
  uint32_t lastState_ = 0;
  uint32_t attnSince_ = 0;
  bool hushed_ = false;      // tapped: no more nudges for this attention
  uint32_t hushAt_ = 0;
  bool ledOverride_ = false, blOverride_ = false;  // dbg.light, until the next state
  uint32_t ledSet_ = 0;
  uint8_t blSet_ = 255;
  Moment moment_;
  Source src_;
  render::Blend blend_;
  LifeEvent life_;
  uint32_t nextLife_ = 0;
  Screen user_ = Screen::kFace;  // face, threads or stats
  uint32_t userAt_ = 0;
  bool pressed_ = false;
  uint32_t pressAt_ = 0, releaseAt_ = 0;
  const char* sfx_ = nullptr;
  uint32_t sfxAt_ = 0;
  uint32_t modelT_ = 0;
  uint32_t momentSeq_ = 0;
};

}  // namespace app
