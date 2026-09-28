// The behaviour state machine (plan/BEHAVIORS.md): what
// the Mac last said, the moment and the mumble playing, blinks, needs
// you, local reactions to inputs, and the light and backlight they imply. Pure C++ and a function of the device clock: every time-based
// change happens at an exact millisecond, so a frozen clock gives the same
// frames on the board and in the simulator. Device owns the I/O.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "app/clock.h"
#include "render/anim.h"
#include "render/scene.h"
#include "render/screens.h"

namespace app {

// kNoApp draws the face screen with the no-app design and the unplugged
// icon (BEHAVIORS.md §3.4).
enum class Screen : uint8_t { kFace, kNeedsYou, kNoApp, kPattern };
const char* screenName(Screen s);

// Copies `src` into a buffer of `n` bytes, cut to fit; null copies as "".
inline void copyStr(char* dst, size_t n, const char* src) { std::snprintf(dst, n, "%s", src ? src : ""); }

// What the Mac last said (PROTOCOL.md §3), as the device parsed it.
struct Model {
  render::SceneState base = render::SceneState::kIdle;  // idle, working or asleep
  render::Mood mood = render::Mood::kHappy;
  // The variation of the look the Mac shows (needs you's while something
  // does, else the base's), from 0: the wire's `variant` less one.
  uint8_t variant = 0;
  bool attn = false;
  char agent[12] = "";
  char project[24] = "";
  char name[24] = "";  // the thread's name; "" when the Mac sends none
  int more = 0;
  uint32_t attnId = 0;  // the request shown's number; 0 when the Mac sends none
  int busy = 0;
  int vol = 6;  // 0–10
};
// `base` by name: working or asleep, and idle for anything else.
render::SceneState baseFromName(const char* name);

// How a moment the Mac waits on ended (PROTOCOL.md §4 `ended`): played to
// the end, cut short, or skipped, none of it played.
enum class MomentEnd : uint8_t { kDone, kCut, kSkipped };
const char* momentEndName(MomentEnd e);
// What cut a moment short: a newer moment, a tap's wiggle, "needs you"
// starting, or dbg.reset.
enum class CutBy : uint8_t { kNone, kMoment, kTap, kNeedsYou, kReset };
const char* cutByName(CutBy c);  // null for kNone

// A moment the Mac waits on that has ended, for Device to send once.
struct Ended {
  uint32_t id = 0;
  MomentEnd how = MomentEnd::kDone;
  CutBy by = CutBy::kNone;  // with kCut
  uint8_t from = 0;         // the moment's own `from`
};

// A moment as it arrives (PROTOCOL.md §3), already held in range. With no
// anim, only the mumble.
struct MomentIn {
  render::Anim anim = render::Anim::kNone;
  int syllables = 0;  // 0: no mumble
  const char* word = nullptr;
  int at = 0;         // the word's place among the syllables, 0..syllables
  uint32_t ms = 120;  // per syllable, 60–400
  // The expression: this mood's version of the look while the moment
  // plays. Only a known mood sets it.
  bool expr = false;
  render::Mood mood = render::Mood::kHappy;
  // The animation's variation (the cheer's), from 0.
  uint8_t variant = 0;
  // 1–Behaviour::kMaxLoops (PROTOCOL.md §3): with the cheer, how many
  // times its design plays; with an expression and no animation, how
  // many loops of the design it's drawn in the face holds. A wiggle
  // ignores it.
  int loops = 1;
  // With the cheer, whose turn it cheers (`who`): named in the strip
  // while it plays. Null for none.
  const char* whoAgent = nullptr;
  const char* whoThread = nullptr;
  // The Mac waits on it when `id` isn't 0 (PROTOCOL.md §3): its end comes
  // back as an Ended with this id and `from`, which is Device's link and
  // passes through untouched.
  uint32_t id = 0;
  uint8_t from = 0;
};

class Behaviour {
 public:
  // Timings (BEHAVIORS.md). Proposed values are marked there.
  static constexpr uint32_t kNoAppMs = 30000;
  static constexpr uint32_t kBubbleReadMs = 1200;  // the word stays up after the mumble
  static constexpr uint32_t kPressEaseMs = 60;     // a press draws at once this long (DEVICE.md §6)
  static constexpr int kPressPx = 2;                // a press dips the face this far
  static constexpr uint32_t kBlinkMs = 180;
  static constexpr int kMaxLoops = 6;  // a moment's `loops` (PROTOCOL.md §3)
  // The looks' variations take turns (BEHAVIORS.md §2): once one has shown
  // kTurnMinMs, each end of its loop moves to another with kTurnPct chance,
  // else it plays another loop.
  static constexpr uint32_t kTurnMinMs = 5000;
  static constexpr int kTurnPct = 67;

  void reset(uint32_t t, Rng& rng);

  // Messages from the Mac, at time t.
  void onState(const Model& m, uint32_t t);
  // True when the moment carries a mumble that will play: not while
  // something needs you.
  bool onMoment(const MomentIn& m, uint32_t t);

  // Inputs, already recognised as gestures.
  void pressDown(uint32_t t);  // visible feedback at once
  void pressUp();
  void tap(uint32_t t);  // BOOT, or a touch anywhere
  // dbg.light: holds the LED and backlight until the next state.
  void overrideLed(uint32_t rgb) { ledOverride_ = true, ledSet_ = rgb; }
  void overrideBacklight(uint8_t level) { blOverride_ = true, blSet_ = level; }

  // Moves to time t, handling every time-based change on the way at its
  // exact millisecond (a moment or mumble ends, a blink, the no-app timeout).
  void advance(uint32_t t, Rng& rng);

  // Queries at t (after advance).
  Screen screen(uint32_t t) const;
  // The face at t: its design, the design's clock, and what the device
  // adds on top (render/scene.h).
  render::SceneShow show(uint32_t t) const;
  // How long the face's design has been playing at t, counting on past its
  // loops: show()'s clock before it wraps a cheer or holds needs you's pose.
  // It starts over only with a new look or a new cheer.
  uint32_t designMs(uint32_t t) const { return src_.anim == render::Anim::kCheer ? t - src_.at : t - lookAt_; }
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
  // The expression the face borrows while its moment plays (PROTOCOL.md
  // §3): true, with its mood, until the moment ends or another replaces it.
  bool expression(uint32_t t, render::Mood& mood) const;
  int syllables() const { return say_.say.syllables; }
  // Counts moments and mumbles started, local ones included, so a line can
  // tell it was replaced.
  uint32_t momentSeq() const { return momentSeq_; }
  // The next moment the Mac waits on that has ended, oldest first, each
  // exactly once; false when there's none (PROTOCOL.md §4).
  bool takeEnded(Ended& e);
  // A blink, Boop's idle life (BEHAVIORS.md §2), is showing.
  bool blinking(uint32_t t) const;
  // What the face is following at t: the animation ("cheer"), or the look
  // ("idle", "working", "asleep", "needs_you", "no_app").
  const char* faceName(uint32_t t) const;
  // When needs you's performance, with its knocks and ding, last started
  // for a new request (BEHAVIORS.md §3.2); false before any.
  bool alerted(uint32_t& at) const {
    at = alertAt_;
    return alerted_;
  }
  const Model& model() const { return model_; }
  // The variation the base's look shows, from 0: the Mac's, until the
  // variations take turns.
  uint8_t lookVariant() const { return lookVariant_; }

 private:
  // Each part of a moment (the animation, the mumble, the expression)
  // carries its moment's id, 0 when the Mac doesn't wait on it.
  struct Moment {
    render::Anim anim = render::Anim::kNone;
    uint8_t variant = 0;  // the cheer's
    uint32_t at = 0, ms = 0;
    uint32_t id = 0;
    char agent[12] = "";  // the cheer's `who`; empty for none
    char thread[24] = "";
  };
  // A mumble: the bubble, and the mouth following the syllables. It plays
  // over whatever face is showing.
  struct Say {
    render::Mumble say;
    char word[24] = "";
    uint32_t at = 0, ms = 0;
    uint32_t speakMs = 0;  // the mouth moves this long
    uint32_t sylMs = 120;
    uint32_t id = 0;
  };
  // A moment the Mac waits on, while any part of it plays: where it came
  // from, and what first cut its animation or its mumble short, if
  // anything.
  struct Waiting {
    uint32_t id = 0;
    uint8_t from = 0;
    CutBy cut = CutBy::kNone;
  };
  // What the Mac is owed, which dbg.reset keeps: the moments it waits on,
  // at most one per part plus the one arriving, and the ends not yet taken.
  // Device takes them after every line and every tick.
  struct Owed {
    static constexpr int kWaiting = 4, kEnded = 8;
    Waiting waiting[kWaiting];
    int nWaiting = 0;
    Ended ended[kEnded];
    int nEnded = 0;
  };
  // What the face is following: an animation or a look, in a mood. A
  // change of design shuts the eyes for kBlendMs, which hides the cut.
  struct Source {
    render::Anim anim = render::Anim::kNone;
    uint32_t at = 0;
    render::SceneState look = render::SceneState::kIdle;  // never kTaskComplete
    uint8_t lookVariant = 0, cheerVariant = 0;
    render::Mood mood = render::Mood::kHappy;
    bool operator==(const Source& o) const {
      return anim == o.anim && at == o.at && look == o.look && lookVariant == o.lookVariant &&
             cheerVariant == o.cheerVariant && mood == o.mood;
    }
    // The design it shows: the cheer's, or the look's, and its variation.
    render::SceneState state() const {
      return anim == render::Anim::kCheer ? render::SceneState::kTaskComplete : look;
    }
    uint8_t variant() const { return anim == render::Anim::kCheer ? cheerVariant : lookVariant; }
    int scene() const { return render::sceneOf(mood, state(), variant()); }
  };

  // The cheer plays `loops` times in `mood`'s design; a wiggle ignores both.
  void play(render::Anim a, uint32_t t, CutBy by, int loops = 1, render::Mood mood = render::Mood::kHappy,
            uint8_t variant = 0);
  // How long a borrowed face in `mood` holds from t: `loops` loops of the
  // design it's drawn in, ending on a loop boundary of that design's clock.
  uint32_t holdMs(render::Mood mood, int loops, uint32_t t) const;
  void startSay(const MomentIn& in, uint32_t t);
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
      if (next.look != src_.look || next.lookVariant != src_.lookVariant) lookAt_ = t;
      src_ = next;
    }
    uint8_t level = blTarget(t);
    if (!blOverride_ && (level != blLevel_ || overridden)) blFade_ = true, blFrom_ = lit, blAt_ = t;
    blLevel_ = level;
    modelT_ = t;
    sweep(t);
  }
  // Moments the Mac waits on: one arriving, a part of one cut short while
  // it plays, and each one with no part left playing at t ended.
  void wait(uint32_t id, uint8_t from);
  void forget(uint32_t id);
  void cut(uint32_t id, CutBy by);
  void sweep(uint32_t t);
  void report(const Ended& e);
  bool holds(uint32_t id, uint32_t t) const;
  void resync(uint32_t t);
  void settle(uint32_t t);
  void startBlink(uint32_t t, Rng& rng);
  uint32_t blinkGap(Rng& rng) const;
  bool momentOn(uint32_t t) const;
  // Something needs you (BEHAVIORS.md §1): a tap or an animation doesn't
  // take the face over.
  bool held(uint32_t t) const;
  uint8_t blTarget(uint32_t t) const;  // the level the state asks for at t
  bool sayOn(uint32_t t) const;
  bool exprOn(uint32_t t) const;
  Source sourceAt(uint32_t t) const;
  // Taking turns: whether the look's variations may take turns at t, the
  // end of the loop playing after t, and the turn itself at a loop's end.
  bool turnable(uint32_t t) const;
  uint32_t loopEnd(uint32_t t) const;
  void turn(uint32_t t, Rng& rng);

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
  // The moment's expression: its mood from exprAt_ for exprMs_: as long as
  // the animation with it plays, or its loops; and at least as long as the
  // mumble with it.
  bool expr_ = false;
  render::Mood exprMood_ = render::Mood::kHappy;
  uint32_t exprAt_ = 0, exprMs_ = 0;
  uint32_t exprId_ = 0;
  Owed owed_;
  Source src_;
  uint32_t lookAt_ = 0;  // when the look's design started
  uint8_t lookVariant_ = 0;  // the base's variation showing
  bool switched_ = false;  // the eyes shut at switchAt_, for a change of design
  uint32_t switchAt_ = 0;
  bool blink_ = false;  // a blink began at blinkAt_, for kBlinkMs
  uint32_t blinkAt_ = 0;
  uint32_t nextBlink_ = 0;
  bool pressed_ = false;
  uint32_t pressAt_ = 0;
  bool alerted_ = false;
  uint32_t alertAt_ = 0;
  uint32_t modelT_ = 0;
  uint32_t momentSeq_ = 0;
};

}  // namespace app
