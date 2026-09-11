# UX: The device

The physical face shows the six states in [Component behaviors](BEHAVIORS.md).
That catalog owns state triggers, duration tiers, folding and the nudge schedule;
this reference owns visual presentation and interaction. Approvals stay entirely in the
editor. Buddy cards are passive attention with no safety labels or decisions. [Wire](WIRE-V2.md) defines transport.

Boot, shutdown and early flow studies remain in [device history](UX-DEVICE-HISTORY.md)
for hardware reference; retired features there are not current requirements.
The dimensions and timings below are visual targets; see [Plan](PLAN.md) for
physical verification status.

## 5. What this assumes

| Assumed | Notes |
| --- | --- |
| A color face canvas | Shape open. Layout rules use "center," "edge," "corner." |
| Primary button | Tap, double tap, hold. The "yes" button. |
| Secondary button | Tap, hold. "No" and "look." Fallback for one button in §12. |
| Speaker | Six motifs. No speech, no music. |
| Motion sensing | Poke, shake, flip, and orientation for posture. |
| Battery and charge state | |
| Bluetooth to the Mac | |
| Touch | Not assumed. If present, affection only. |

## 6. Doctrine

1. **Idle is simple, need is loud.** Layers are added in a fixed order:
   color, motion, sound, card.
2. **At rest the screen is the face and nothing else.**
3. **Light is spent on need.** Only Needs you and Uh-oh brighten the field.
   Done gets a ripple, not a field.
4. **Buttons are the only actuators.** Motion and touch never decide.
5. **Urgency beats affection.** Greet and Boop overlay calm states only.
6. **The cheer scales.** Hop is common, Dance is rare.
7. **Nothing teleports, nothing blocks, everything breathes.**
8. **Text only in the card or the bubble.**
9. **One creature.**
10. **Feelings are about the work.** No expression is aimed at the owner.

## 7. Anatomy

Revised 2026-09-09 (owner decision): **the buddy is a face, not a body.**
The screen is black; the eyes and mouth float on it. What the old body
carried (energy, posture, skin) lives in the eyes themselves and in the
field wash. There is no glow: on the 8-bit sprite a gradient collapses
into a hard disc, so nothing is ever drawn behind the eyes.

Amended 2026-09-11 (owner: "the agent can have a small/tiny body — or
maybe just arms? — that can point and wave too, make this very cute").
**Arms are now allowed; a body still is not.** There is no torso, no
legs, no outline and nothing joining the two arms. An arm follows the
brow's rule rather than the eyes': it exists only while it is doing
something, and it leaves when the moment does, so at rest the face is
still two eyes and a mouth on black. Arms appear in exactly three
moments — the hello wave, the celebration, and the dashboard gesture —
and never while a card is up.

| Part | Carries | Range |
| --- | --- | --- |
| Eyes | Attention, mood | Open, half, closed, wide, arc, small circles; look any direction; blink |
| Brows | Effort, surprise | Neutral, raised, furrowed |
| Mouth | Mood | Neutral, smile, open smile, flat, small o |
| Cheeks | Affection, exertion | Blush, sweat drop |
| Eye ink | Energy, skin | Bright ink awake, dimmer asleep, grey before first contact; skins tint it. Bob, lean, squish and hop move the whole face. |
| Arms | Greeting, celebration, pointing | Absent at rest. A tapered stroke from a shoulder below and outside an eye, ending in a mitten; swings about the shoulder. Drawn in the eye ink. |
| Field | Need | Black, amber wash `(72,36,0)`, red wash `(72,0,0)` |
| Sparks | Celebration, affection | Five confetti dots, one rose heart |
| Accessories | Cosmetics | Small, above or beside the eyes, drawn in the eye ink, never over the eyes or the card |

Eyes are the anchor, centered and largest: 64×80 px at rest, 96 px apart,
wider on Needs you. Gaze offsets stay small (±6 px drifting, 8 px down-left
while working) so the pair never leaves the middle of the screen. Every part has a resting
micro-motion. Expressions are blends of parts, not separate sprites.
Appearance is fixed; the anchor never moves. No outlines anywhere: every shape is a filled, smooth edge.

**Palette (2026-09-11).** The device and the Mac app share one palette,
"Boop Cream", and invert the field. The app is cream paper with warm ink;
the device keeps the ink and puts it on black. Black is free on AMOLED —
the pixels are off — and a cream field would light all 456×280 of them,
cost battery, glow in a dark room, and burn in under a persistent
dashboard. Pure white ink on black is harsh at night, so the ink is a
warm cream that reads as lamp light and matches the app's paper.

Every device colour sits exactly on the RGB332 lattice the 8-bit canvas
quantizes to (R, G ∈ {0, 36, 73, 109, 146, 182, 219, 255}; B ∈ {0, 82,
173, 255} — four levels only). Off-lattice values snap silently. Blue is
the scarce channel, which is why the palette is warm. The constants live
in `firmware/esp32/firmware/palette.h`; the app's half is
`app/Boop/Theme/BuddyTheme.swift`.

| Token | Value | Use |
| --- | --- | --- |
| Paper | `255,219,173` | The ink: face, text, dashboard counts |
| Paper soft | `219,182,146` | Column heads, units, the card's gloss |
| Paper dim | `146,109,82` | Asleep; a zero count |
| Paper faint | `73,73,73` | Grey before first contact |
| Amber | `255,182,36` | Needs you, and only that |
| Sage | `109,219,146` | Done; an idle count worth acting on |
| Rose | `255,109,173` | Affection: the heart and the blush |
| Sky | `73,146,255` | Link glyph, sweat drop |

The three semantic tones mean the same thing on both screens, so a colour
is learnable once. Amber never marks a primary action — the app uses
terracotta for that, and the device has no actions to mark.

**Blends quantize harder than endpoints (2026-09-11).** `animMix` lerps in
RGB565 and the canvas then *truncates* to RGB332 (`R5>>2`, `G6>>3`,
`B5>>3`). A blend therefore lands on a much coarser grid than the endpoint
lattice above suggests, and it loses hue as it darkens because R and G shed
different numbers of bits. This had silently broken the field: a 0.14 mix
toward amber and a 0.18 mix toward red both resolved to `(36,0,0)`, so
**"needs you" and "uh-oh" were rendering the identical colour.** The wash
now mixes toward Amber deep `182,109,0`, whose lower G/R ratio survives the
truncation. Rest is `(72,36,0)`; the second nudge rung peaks at
`(109,72,0)`; uh-oh sits at `(72,0,0)` rising to `(109,0,0)`. The two
states differ by hue, at matched brightness.

The first nudge rung's gentle breath (0.40 → 0.51) stays inside one bucket
and renders as a flat field. That is the lattice's floor, not an oversight:
the face breathes, so the field does not have to. Choose any new wash
against the real path, not against the endpoint lattice.

## 8. States

| State | Eyes | Body | Field | Sound |
| --- | --- | --- | --- | --- |
| **Asleep** | Closed | Slow breathing, occasional twitch, lowest brightness, never off | Dark | none |
| **Idle** | Open, drifting, blinking | Gentle bob, micro-idles | Dark | none |
| **Working** (effort: light / hard / grinding) | Down and away | Lean in → sweat → tremble | Dark | none |
| **Needs you** | Wide, at you | Turns, leans forward | Amber | "meep?" |
| **Done** (size: hop / cheer / dance) | Arc | Hop → cheer → dance | Green ripple | blip → chirp → fanfare |
| **Uh-oh** | Half, down | Slump | Dim red, breathing | one low note |

Overlays, on idle, working, and done only. Never on asleep (a booped
sleeper gets the one-eye peek, not hearts), never on needs you or uh-oh:

| Overlay | Trigger | Look |
| --- | --- | --- |
| **Greet** | Link after time away | Squish and bounce, scaled to absence; bubble at a day or more |
| **Boop** | Primary tap or pet with nothing pending | Squish, smile, one heart per boop; giggle blip. No blush — see §20 |

Motion reactions in any state: shake gives three seconds of small-eye wobble,
flip face-down naps. Both are suppressed while a prompt is on screen.

There is no separate thinking, stuck, hungry, focus, or link-lost state.
Thinking and silence remain Working until an explicit lifecycle signal.
Uh-oh is reserved for explicit errors. Quiet mode has no visual marker. Link lost is Idle glancing at a dim Bluetooth
mark in the corner, then Travel. Unpaired is the same mark, pulsing, with
the buddy looking at it hopefully.

## 9. The cheer

Sizes and triggers follow [duration tiers](BEHAVIORS.md#3-effort-and-celebrations). No cheer sound twice within ten seconds;
the second is silent. Needs you and Uh-oh take priority; the cheer timer keeps
running while hidden and there is no guaranteed replay. Nearby completions
fold within 3 s. No gift or collection remains. Optional model dialogue is considered after the celebration returns to idle.

## 10. The card

Revised 2026-09-09. There is one card. It is used for Needs you, for the
pairing code, and for firmware updates. Same position (lower third, eyes
visible above), same motion (rises from the bottom edge, settles, leaves
the same way), same type. Users learn one card.

**No box.** The card is not a bordered panel. It is two lines of text on
the black field under the face, with the field's amber wash as the only
frame. Proportional type, the bundled Korean-capable face; one size for
the tool name (medium weight) and one for the gloss (regular).

Needs-you uses a borderless 88 px footer on landscape screens, showing tool,
queue count and up to two lines of supplied reason. Text uses the full footer
width with UTF-8-safe overflow. The face lifts 25 px and eyes enlarge 20% while
the card is visible. System cards keep their layout.

No stakes dot, yes/no labels, decision holds, arming or acknowledgement feedback.
A button dismisses a passive card locally, suppressing reminders for that ID.
A new request starts fresh. Wake presses remain consumed.



Nudge ladder, chosen by the app, rendered by the device:

| Rung | Default | Device |
| --- | --- | --- |
| 0 | On arrival | Amber, turn, one "meep?" |
| 1 | 60 seconds | One soft "meep?", small lean |
| 2 | 120 seconds | Stronger sound, brief field pulse |
| Quiet mode | Enabled | All sounds muted; visual rungs and timing unchanged |

Dismissal resets the rung and snoozes this request only. No generated hush line.

## 11. Postures

**Desk.** The set in §8. Upright, faces the owner, has a floor.

**Perch.** On the top corner of the lid, looking down at the work.

| State | Perch version |
| --- | --- |
| Idle | Feet dangle and kick slowly, gazes down at the screen, looks up at you now and then |
| Working | Leans over the edge; grinding grips the edge, feet tucked |
| Needs you | Peers straight down at you, tips its head |
| Done | Hops on the corner; Dance adds a jump-and-land wobble |
| Uh-oh | Sags, feet stop |
| Asleep | Curls in the corner |
| Greet | Pops up over the edge as if hiding |

Perch is the posture other people see, so its idle is the richest.

**Travel.** Unplugged, unlinked. Idle with more frequent micro-idles and a
battery mark below a quarter. Enters after a minute of lost link on
battery, via a yawn. No "disconnected" text, ever.

Posture detection: upright and still is desk; tilted to lid angle and held
is perch; moving or unlinked on battery is travel. Ambiguous keeps the last
posture; never flicker.

## 12. Buttons

Context first: a passive attention card can be dismissed; a bubble can be
cleared; otherwise primary tap boops and existing stats gestures remain.
Motion never resolves a request. Wake presses are consumed. Secondary hold
retains Quiet mode and shutdown behavior. No approval tap, deny hold, careful
hold, arming guard or decision feedback remains.


## 13. Travel mode and stats

Two cards, summoned by double tap or the secondary button, auto-dismiss in
ten seconds. Big type, one fact per line, no charts, safe to show anyone.

1. **The buddy.** Name, cumulative XP, streak with a small flame. The buddy
   stands beside it with its fixed appearance and strikes a proud pose.
2. **Together.** Days together, tasks done, biggest cheer, today's tally
   from the last sync (dated if older than a day).

Nothing about projects or habits appears here.

Travel interactions: tap to boop, hold to pet, shake for dizzy, flip to
nap, pick up to perk up. No menu, no settings. Everything is demonstrable to
a friend in five seconds.

**Stats look (revised 2026-09-09).** No panel, no border. The face slides
left and shrinks to its arc-eyed proud pose; the right two thirds carry
the snapshot as three lines in proportional type: the name (medium), then
`7-day streak`, then cumulative `320 XP`. No level or progress bar. All stats text uses eye ink.
Page two: `12 days together`, `84 turns`, the largest celebration from the last snapshot, `today: 6`. Numbers are formatted with the app's
localizer; the device never composes sentences.

## 14. Rituals

First wake and greeting are deterministic physical animations. The model chooses
any greeting text. Level-up light sweeps and streak pulses remain visual feedback;
there are no cosmetic unlocks or newly created milestone keepsakes. Retirement
is not exposed in Settings.

## 15. Sound

Seven interaction/completion motifs plus the stronger nudge. Each under 700 ms, each
tellable from the others across a room with eyes closed.

| State | Motif |
| --- | --- |
| Needs you | Rising two-note "meep?" |
| Done · hop | One bright blip |
| Done · cheer | Two-note chirp |
| Done · dance | Four-note fanfare |
| Uh-oh | One low note |
| Greet | Cheerful two-note |
| Boop | Soft giggle blip |

Manners: sounds are separated by at least a second; cheer sounds do not repeat
within ten seconds. Normal volume is fixed at step 1. Quiet mode mutes every
motif, including requests and errors. The stronger nudge uses an additional
motif. Current Waveshare hardware has no speaker.

## 16. Text, priority, dim

- Text lives in the card and the bubble. Bubbles are plain text in the eye
  ink beside the face, no pill and no box (8-bit fills read as mud), one
  line, two at most, four seconds or any button. The app truncates.
- The card footer (2026-09-11) carries one hairline across its top — still
  no box and no fill, but the rule separates the question from the face.
  The tool name and the gloss share the left edge; the tool was indented
  14 px past the gloss and the two read as a ragged pair. The tool is the
  cream ink and the gloss steps down to the soft ink, so the tool name is
  what the eye lands on first.
- The device font must render launch languages including Korean legibly.
- Screen priority, highest wins: system card → Needs you card  → Uh-oh bubble → stats → bubble → overlay → face. Lower
  layers keep simulating.
- Brightness: 210/255 awake, 255 with a card, 90 after two minutes with
  no button and no agent activity, 28
  asleep. The screen never turns itself off. A pending prompt never dims.
  A state change from the app counts as activity: a working buddy is
  never dim.

## 17. Micro-idles

Only while Idle, at least ninety seconds apart, under two seconds each:
yawn, look slowly across the canvas, happy wiggle, one slow look at you,
head tilt. Perch adds a slow dangle of the gaze; Travel adds looking around the
room. Never within ten seconds of a real interaction.

## 18. Appearance

Default skin, no accessory and default silhouette. Old saved choices remain
inactive. XP does not unlock appearance or behavior.

## 20. Motion language

Revised 2026-09-09 (owner: "simple and cute"). Every animation is one
clear motion with a beginning and an end. Nothing scrolls across the
screen, nothing swarms, nothing spins.

**Rules.**

- One motion per moment. If two things want to move, the smaller one
  waits or is dropped.
- Arrivals spring (about 6% overshoot); departures ease out. Durations
  150–900 ms; the dance is the only thing longer, and it ends at 2.5 s.
- Sparks are few and soft: one heart, at most five confetti dots, all
  filled circles, never rectangles or lines. Sparks fade out rather than
  blinking off; a group of hard dots vanishing on the same frame is what
  made the celebration look busy.
- The eyes carry the emotion. Squash and stretch the eyes before moving
  anything else.
- Feet, torsos, particles behind the face: none. Arms are the one
  exception (§7) and obey the same rules: one motion, a beginning and an
  end, and never at the same time as a card.

**The moments.**

| Moment | Motion |
| --- | --- |
| Blink | Lids close 110 ms every ~5 s. Unchanged. |
| Idle | Slow bob (±3 px, 1.4 s), gaze drifts. Micro-idles are small: gaze lap ±20 px, wiggle ±6 px. |
| Working | Reading: eyes narrow to 85% and the gaze hops between two spots low on the page (8 px left, 7 px right) every 1.6 s, eased, with a small lean; hard adds the brow and the sweat drop (one drop slides 18 px every 3 s); grinding adds a faint tremble (±1.5 px). |
| Needs you | Eyes spring wide, tiny lean toward you. |
| Boop (tap, pet) | Eyes squish to 60% height for 250 ms and spring back; smile; **one heart**. Revised 2026-09-11 (owner: "has too much going on… if the heart is in the middle it looks like a weird pimple"): **no blush**, and the heart no longer rises from the gap between the eyes. It now rises **diagonally off the left side of the face** — starting beside the cheek at eye-centre +30 px, clear of the eye, and drifting 34 px out and 64 px up over 1 s. Scale 0→1 in 170 ms with 6% overshoot, radius 14, rose; shrinks away over the last 150 ms. Centred, a heart sits on the face like a blemish instead of reading as something the buddy gives off. Left, because the greeting wave is the right arm and level‑3 greet grants a heart at the same time — on the same side they overlap, on opposite sides the pose is balanced. One heart per boop; holding or petting adds none, and at most one heart every 2.5 s. A further boop inside that window still squishes and smiles but grants no heart, so a long petting session reads as an affectionate beat now and then rather than a stream. The cooldown is applied where the boop is registered, not in the renderer, so one clock owns it. |
| Greet, level 1 | One slow blink and a smile. |
| Greet · wave | One arm raises over 240 ms and waves at ~2.2 Hz (±0.30 rad about 2.50 rad from straight down) for the whole 2.2 s greeting window, then retracts over 320 ms. It runs across all greet levels: a hand that appears and vanishes inside 600 ms reads as a glitch, not a hello. |
| Greet, level 2 | One squash-and-stretch bounce (bob −16 px, spring) and blush. |
| Greet, level 3 | Two bounces and one heart (heart left, wave right). |
| Done · hop | Arc eyes, smile, one bounce (−21 px, spring). No ring, no sparks. |
| Done · cheer | Arc eyes, blush, two bounces, a small head wag (tilt ±0.12 rad, twice). No spin. |
| Done · dance | Arc eyes, blush, bounces at 2 Hz with a side sway (tilt ±0.25 rad at 1.5 Hz) for 2.5 s, **both arms raised** (2.55 rad, swinging ±0.26 rad in opposition so it reads as a cheer rather than a shrug), and five confetti dots: radius 3, rose / sage / gold, each starting above the eyes at a fixed x and drifting down 100 px over the dance with a gentle sway, each fading out over its last third. |
| Done · cheer arms | Both arms raise over 220 ms to 2.45 rad, swing ±0.20 rad in opposition, and retract over 280 ms. Arms go up, not out: at 2.30 rad the hands reached nearly to both screen edges and the pose read as stretched. |
| Uh-oh | Slump (lean 12, eyes half) and slow bob. Unchanged. |
| Shake (dizzy) | Eyes shrink to 20 px circles and the gaze wobbles ±10 px for 3 s. No X-lines. |
| Pick-up | Perk: eyes wide, lean back 8 px. Unchanged. |
| Level up | Removed; cumulative XP has no level milestones. |
| Streak | The small flame pulses gently beside the face. |
| Card | Springs up, eases away. Unchanged. |

## Agent availability dashboard (2026-09-11)

This supersedes duration-based device cheers and the face-only presentation
for mixed activity. The desktop retains its own celebrations.

- All working: full-size working face. All idle: full-size idle face with a
  green `N idle` footer. No sessions: ordinary idle/sleep lifecycle.
- Working and idle sessions coexist: the buddy shrinks into the upper-right
  corner while pulling in a count board over 550 ms. It remains there,
  presenting the idle column from directly above it: anticipatory squish, two downward nods, a rosy smile back at the owner, then rest. The 5.6-second loop starts on entry; the separate arrow is removed.
  The board stays until the mixed state ends; there is no timeout or unread state.
- **Gesture (2026-09-11).** From 1.15 s a little arm reaches out over
  260 ms and gestures down across the board at about 0.52 rad from
  straight down, tapping twice (±0.20 rad) on the beat of the nods, and
  retracts by 4.4 s. The counts never move: only the buddy does. The hand
  lands in the gap above the column heads, never on them.
- **Proportions (2026-09-11).** The board takes precedence here, so the
  buddy shrinks — but to 42%, not 28%. At 28% it stopped reading as a
  creature and became two dots and a mouth. The face sits at 83% width and
  y = 46, clear of the top edge. The table is centred in the band below it
  (y 108 to H−20) rather than pinned to a fixed top: with one or two agents
  a fixed top left ~80 px of dead screen and the whole board sat high.
  One hairline runs under the column heads — no box and no fill, per §16,
  but a rule is what turns loose pairs of numbers into a table.
- Rows are Codex, Claude, Cursor and Other, in stable order, omitting sources
  with no tracked sessions. Columns are WORKING and IDLE (WORK on narrow M5).
  A non-zero idle count is sage; other non-zero counts are the cream ink;
  a zero is dimmed rather than dropped, so the columns stay aligned and the
  eye lands on the counts that are actually worth acting on.
  The fixed harness names and English headers use the built-in proportional
  Font2 at 1.5× on Waveshare (0.75× on M5); request/bubble Korean text keeps
  its existing font. No session names, automatic paging, acknowledgment or
  dismissal bookkeeping.
- Counts update in place. When all sessions work or all are idle, the board
  slides away and the buddy grows back. All-idle taps retain boop affection.
- Explicit requests/errors, system cards, sleep/disconnection and user-opened
  stats retain priority. Waiting/error sessions count as neither working nor idle.
- Idle means an available tracked session, not an unread result. Session end
  and the existing stale-session cleanup remove entries; no view hook is needed.

Physical motion and font legibility must be verified on the target display.
