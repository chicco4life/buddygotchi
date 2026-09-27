// The behaviour state machine (plan/BEHAVIORS.md, plan/UX.md §3–4): what
// the Mac last said, the moment and the mumble playing, idle life, needs
// you, local reactions to inputs, and the light, backlight and sound cues
// they imply. Pure C++ and a function of the device clock: every time-based
// change happens at an exact millisecond, so a frozen clock gives the same
// frames on the board and in the simulator. Device owns the I/O.
#pragma once
#include <cstdint>

#include "app/clock.h"
#include "render/anim.h"
#include "render/scene.h"
#include "render/screens.h"

namespace app {

// kNoApp draws the face screen with the no-app design and the unplugged
// icon (BEHAVIORS.md §3.4).
enum class Screen : uint8_t { kFace, kNeedsYou, kNoApp, kPattern };
const char* screenName(Screen s);

// What the Mac last said (PROTOCOL.md §3).
struct Model {
  char base[12] = "idle";
  render::Mood mood = render::Mood::kHappy;
  bool attn = false;
  char agent[12] = "";
  char project[24] = "";
  int more = 0;
  int busy = 0, idle = 0, wait = 0;
  int vol = 6;
};

// A moment as it arrives (PROTOCOL.md §3). With no anim, only the mumble.
struct MomentIn {
  render::Anim anim = render::Anim::kNone;
  int syllables = 0;  // 0: no mumble
  const char* word = nullptr;
  int at = -1;
  uint32_t ms = 120;  // per syllable
};

// Idle life: small things Boop does on its own (BEHAVIORS.md §2).
enum class Life : uint8_t { kNone, kBlink };
const char* lifeName(Life l);

class Behaviour {
 public:
  // Timings (BEHAVIORS.md, UX.md). Proposed values are marked there.
  static constexpr uint32_t kNoAppMs = 30000;
  static constexpr uint32_t kBubbleReadMs = 1200;  // the word stays up after the mumble
  static constexpr uint32_t kPressEaseMs = 60;     // a press draws at once this long (DEVICE.md §6)
  static constexpr int kPressPx = 2;                // a press dips the face this far
  static constexpr uint32_t kBlinkMs = 180;

  void reset(uint32_t t, Rng& rng);

  // Messages from the Mac, at time t.
  void onState(const Model& m, uint32_t t);
  // True when the moment carries a mumble that will play: not while
  // something needs you.
  bool onMoment(const MomentIn& m, uint32_t t);

  // Inputs, already recognised as gestures (UX.md §4).
  void pressDown(uint32_t t);  // visible feedback at once
  void pressUp(uint32_t t);
  void tap(uint32_t t);  // BOOT, or a touch anywhere
  // dbg.light: holds the LED and backlight until the next state.
  void overrideLed(uint32_t rgb) { ledOverride_ = true, ledSet_ = rgb; }
  void overrideBacklight(uint8_t level) { blOverride_ = true, blSet_ = level; }

  // Moves to time t, handling every time-based change on the way at its
  // exact millisecond (a moment or mumble ends, idle life, the no-app timeout).
  void advance(uint32_t t, Rng& rng);

  // Queries at t (after advance).
  Screen screen(uint32_t t) const;
  // The face at t: its design, the design's clock, and what the device
  // adds on top (render/scene.h).
  render::SceneShow show(uint32_t t) const;
  // A press has just come in: feedback the redraw cap mustn't hold back
  // (DEVICE.md §6).
  bool pressEasing(uint32_t t) const;
  bool noApp(uint32_t t) const;
  uint32_t led(uint32_t t) const;
  uint8_t backlight(uint32_t t) const;
  render::Strip strip(uint32_t t) const;
  // The mumble in the bubble, or null.
  const render::Mumble* mumble(uint32_t t) const;
  // The animation playing (kNone for none) and ms left.
  render::Anim moment(uint32_t t, uint32_t& left) const;
  bool speaking(uint32_t t) const;
  int syllables() const { return say_.say.syllables; }
  // Counts moments and mumbles started, local ones included, so a line can
  // tell it was replaced.
  uint32_t momentSeq() const { return momentSeq_; }
  Life life(uint32_t t) const;
  // What the face is following at t: the animation ("cheer"), or the look
  // ("idle", "working", "asleep", "needs_you", "no_app").
  const char* faceName(uint32_t t) const;
  const char* sfx(uint32_t& at) const {
    at = sfxAt_;
    return sfx_;
  }
  const Model& model() const { return model_; }

 private:
  struct Moment {
    render::Anim anim = render::Anim::kNone;
    uint32_t at = 0, ms = 0;
  };
  // A mumble: the bubble, and the mouth following the syllables. It plays
  // over whatever face is showing.
  struct Say {
    render::Mumble say;
    char word[24] = "";
    uint32_t at = 0, ms = 0;
    uint32_t speakMs = 0;  // the mouth moves this long
    uint32_t sylMs = 120;
  };
  // What the face is following: an animation or a look, in a mood, and a
  // mumble on top. A change of design shuts the eyes for kBlendMs, which
  // hides the cut (UX.md §2).
  struct Source {
    render::Anim anim = render::Anim::kNone;
    uint32_t at = 0;
    render::Look look = render::Look::kIdle;
    render::Mood mood = render::Mood::kHappy;
    bool say = false;
    uint32_t sayAt = 0, speakMs = 0, sylMs = 0;  // the mouth follows the syllables
    bool operator==(const Source& o) const {
      return anim == o.anim && at == o.at && look == o.look && mood == o.mood && say == o.say &&
             sayAt == o.sayAt && speakMs == o.speakMs && sylMs == o.sylMs;
    }
    // The design it shows: the cheer's, or the look's.
    render::SceneState state() const;
    int scene() const { return render::sceneOf(mood, state()); }
  };
  struct LifeEvent {
    Life kind = Life::kNone;
    uint32_t at = 0, ms = 0;
  };

  void play(render::Anim a, uint32_t t);
  void startSay(const MomentIn& in, uint32_t t);
  void sound(const char* k, uint32_t t);
  // Every change goes through here: `f` changes the state at t, and if
  // what the face follows changed to another design, the eyes shut for a
  // moment; a new look starts its design's clock. The backlight eases from
  // the level that was showing.
  template <class F>
  void change(uint32_t t, F f) {
    uint8_t lit = backlight(t);
    bool overridden = blOverride_;
    f();
    Source next = sourceAt(t);
    if (!(next == src_)) {
      // Another design, or the cheer's design starting over for a new cheer.
      bool restart = next.anim == render::Anim::kCheer && next.at != src_.at;
      if (next.scene() != src_.scene() || restart) switched_ = true, switchAt_ = t;
      if (next.look != src_.look) lookAt_ = t;
      src_ = next;
    }
    uint8_t level = blTarget(t);
    if (!blOverride_ && (level != blLevel_ || overridden)) blFade_ = true, blFrom_ = lit, blAt_ = t;
    blLevel_ = level;
    modelT_ = t;
  }
  void resync(uint32_t t);
  void settle(uint32_t t);
  void startLife(uint32_t t, Rng& rng);
  uint32_t lifeGap(Rng& rng) const;
  bool momentOn(uint32_t t) const;
  // Something needs you (BEHAVIORS.md §1): a tap or an animation doesn't
  // take the face over.
  bool held(uint32_t t) const;
  uint8_t blTarget(uint32_t t) const;  // the level the state asks for at t
  bool sayOn(uint32_t t) const;
  Source sourceAt(uint32_t t) const;

  Model model_;
  uint32_t lastState_ = 0;
  // Latched once the Mac has been silent kNoAppMs, so "no app" holds
  // however long the silence (the clock's differences wrap after 24 days).
  bool stale_ = false;
  bool ledOverride_ = false, blOverride_ = false;  // dbg.light, until the next state
  uint32_t ledSet_ = 0;
  uint8_t blSet_ = 255;
  // The level the state asked for at the last change, like src_ for the
  // face, easing from blFrom_ since blAt_, over kBlendMs.
  uint8_t blLevel_ = 255;
  bool blFade_ = false;
  uint8_t blFrom_ = 255;
  uint32_t blAt_ = 0;
  Moment moment_;
  Say say_;
  Source src_;
  uint32_t lookAt_ = 0;  // when the look's design started
  bool switched_ = false;  // the eyes shut at switchAt_, for a change of design
  uint32_t switchAt_ = 0;
  LifeEvent life_;
  uint32_t nextLife_ = 0;
  bool pressed_ = false;
  uint32_t pressAt_ = 0;
  const char* sfx_ = nullptr;
  uint32_t sfxAt_ = 0;
  uint32_t modelT_ = 0;
  uint32_t momentSeq_ = 0;
};

}  // namespace app
