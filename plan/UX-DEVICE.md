# UX: The device

The physical face shows the six states in [Component behaviors](BEHAVIORS.md).
That catalog owns state triggers, duration tiers, folding and the nudge schedule;
this reference owns visual presentation and interaction. Approvals stay in the
editor by default. Actionable Buddy cards require explicit opt-in; passive
attention cards have no approval buttons. [Wire](WIRE-V2.md) defines transport.

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
The screen is black; the eyes and mouth float on it. There is no drawn
body shape, ever. What the old body carried (energy, posture, skin) now
lives in the eyes themselves and in the field wash. There is no glow
either: on the 8-bit sprite a gradient collapses into a hard disc, so
nothing is ever drawn behind the eyes.

| Part | Carries | Range |
| --- | --- | --- |
| Eyes | Attention, mood | Open, half, closed, wide, arc, small circles; look any direction; blink |
| Brows | Effort, surprise | Neutral, raised, furrowed |
| Mouth | Mood | Neutral, smile, open smile, flat, small o |
| Cheeks | Affection, exertion | Blush, sweat drop |
| Eye ink | Energy, skin | Bright ink awake, dimmer asleep, grey before first contact; skins tint it. Bob, lean, squish and hop move the whole face. |
| Field | Need | Black, amber wash, dim red wash |
| Sparks | Celebration, affection | Six confetti dots, one pink heart |
| Accessories | Cosmetics | Small, above or beside the eyes, drawn in the eye ink, never over the eyes or the card |

Eyes are the anchor, centered and largest: 64×80 px at rest, 96 px apart,
wider on Needs you. Gaze offsets stay small (±6 px drifting, 8 px down-left
while working) so the pair never leaves the middle of the screen. Every part has a resting
micro-motion. Expressions are blends of parts, not separate sprites.
Silhouettes change eye spacing and size at level milestones; the anchor
never moves. No outlines anywhere: every shape is a filled, smooth edge.

## 8. States

| State | Eyes | Body | Field | Sound |
| --- | --- | --- | --- | --- |
| **Asleep** | Closed | Slow breathing, occasional twitch, lowest brightness, never off | Dark | none |
| **Idle** | Open, drifting, blinking | Gentle bob, micro-idles | Dark | none |
| **Working** (effort: light / hard / grinding) | Down and away | Lean in → sweat → tremble | Dark | none |
| **Needs you** | Wide, at you | Turns, leans forward | Amber | "meep?" |
| **Done** (size: hop / cheer / dance) | Arc | Hop → spin → dance | Green ripple | blip → chirp → fanfare |
| **Uh-oh** | Half, down | Slump | Dim red, breathing | one low note |

Overlays, on idle, working, and done only. Never on asleep (a booped
sleeper gets the one-eye peek, not hearts), never on needs you or uh-oh:

| Overlay | Trigger | Look |
| --- | --- | --- |
| **Greet** | Link after time away | Squish and bounce, scaled to absence; bubble at a day or more |
| **Boop** | Primary tap or pet with nothing pending | Squish, blush, mini hearts while held; giggle blip |

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

Needs you layout, revised 2026-09-10: a borderless 88 px bottom footer on
landscape screens. The left column contains the stakes mark and tool, with
a quiet queue count beside it, followed by up to two lines of gloss.
Overflow ends in an ellipsis at a UTF-8 boundary. The right column shows
`Press: yes` / `Hold: no`, or `Hold 2s: yes` / `Side: no` for careful prompts.
Labels appear immediately and remain visible during interaction. The landscape
approval/decision face is lifted only 25 px (22 px lower than the first footer
iteration), with eyes enlarged by 20% in both dimensions. The enlargement
eases with the card; system cards and compact side layouts keep their sizing. Portrait
screens stack instructions below the gloss. System cards retain their layout.

No persistent ring. During a hold, an underline beneath the relevant action
fills over 1 s (deny) or 2 s (careful approval), draining on early release.
The 600 ms arming guard is unchanged. Labels and queue count use grey
`animRGB(146,146,146)`. Feedback occupies the same footer after a decision.

Decision feedback replaces the card: `yes!` / `okay` in the tool-line
position for 1.5 s, then the face returns. `sending...` appears immediately
while awaiting acknowledgement; `no link?` replaces it after 3 s.

Nudge ladder, chosen by the app, rendered by the device:

| Rung | Default | Device |
| --- | --- | --- |
| 0 | On arrival | Amber, turn, one "meep?" |
| 1 | 60 seconds | One soft "meep?", small lean |
| 2 | 120 seconds, every stakes level | Stronger sound, brief field pulse |
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

| | Tap | Double tap | Hold |
| --- | --- | --- | --- |
| **Primary** | Yes: approve → clear bubble → boop | Boop (connected) · stats (travel) | Deny (1 s, armed prompt) · approve red dot (2 s) · pet (otherwise) |
| **Secondary** | No: deny → dismiss → next stats card → "hmph" flick | | Quiet mode toggle (1 s) · shutdown ladder (3 s) |

Primary tap resolves first match: armed prompt → bubble →
boop. "Primary means yes" stays one verb.

Without a secondary button: deny stays on primary hold, Quiet mode is a triple
tap, stats page by repeated double tap, shutdown is a long primary hold with
the same staged feedback.

## 13. Travel mode and stats

Two cards, summoned by double tap or the secondary button, auto-dismiss in
ten seconds. Big type, one fact per line, no charts, safe to show anyone.

1. **The buddy.** Name, level, XP bar, streak with a small flame. The buddy
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
`Level 4 · 7-day streak`, then the XP bar: a thin track with a filled
rounded bar in `GREEN` on a pure grey `animRGB(146,146,146)` track,
with `320 / 500` right-aligned above it. All stats text uses eye ink.
Page two: `12 days together`, `84 tasks`, the largest celebration from the last snapshot, `today: 6`. Numbers are formatted with the app's
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
- The device font must render launch languages including Korean legibly.
- Screen priority, highest wins: system card → Needs you card → decision
  feedback → Uh-oh bubble → stats → bubble → overlay → face. Lower
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
- Sparks are few and soft: one heart, at most six confetti dots, all
  filled circles, never rectangles or lines.
- The eyes carry the emotion. Squash and stretch the eyes before moving
  anything else.
- Feet, bodies, particles behind the face: none.

**The moments.**

| Moment | Motion |
| --- | --- |
| Blink | Lids close 110 ms every ~5 s. Unchanged. |
| Idle | Slow bob (±3 px, 1.4 s), gaze drifts. Micro-idles are small: gaze lap ±20 px, wiggle ±6 px. |
| Working | Reading: eyes narrow to 85% and the gaze hops between two spots low on the page (8 px left, 7 px right) every 1.6 s, eased, with a small lean; hard adds the brow and the sweat drop (one drop slides 18 px every 3 s); grinding adds a faint tremble (±1.5 px). |
| Needs you | Eyes spring wide, tiny lean toward you. |
| Boop (tap, pet) | Eyes squish to 60% height for 250 ms and spring back; blush; smile; **one heart**: it pops in 12 px above the gap between the eyes (scale 0→1 in 150 ms, 6% overshoot, radius 10, pink), floats up 24 px over 900 ms, shrinks away in the last 100 ms. One heart per boop; holding or petting adds none. |
| Greet, level 1 | One slow blink and a smile. |
| Greet, level 2 | One squash-and-stretch bounce (bob −16 px, spring) and blush. |
| Greet, level 3 | Two bounces and one heart. |
| Done · hop | Arc eyes, smile, one bounce (−21 px, spring). No ring, no sparks. |
| Done · cheer | Arc eyes, blush, two bounces, a small head wag (tilt ±0.12 rad, twice). No spin. |
| Done · dance | Arc eyes, blush, bounces at 2 Hz with a side sway (tilt ±0.25 rad at 1.5 Hz) for 2.5 s, and six confetti dots: radius 4, pink / mint / gold, each starting above the eyes at a fixed x and drifting down 100 px over the dance with a gentle sway; gone at the end. |
| Uh-oh | Slump (lean 12, eyes half) and slow bob. Unchanged. |
| Shake (dizzy) | Eyes shrink to 20 px circles and the gaze wobbles ±10 px for 3 s. No X-lines. |
| Pick-up | Perk: eyes wide, lean back 8 px. Unchanged. |
| Level up | Light sweep across the eyes, one soft field flash. |
| Streak | The small flame pulses gently beside the face. |
| Card | Springs up, eases away. Unchanged. |
