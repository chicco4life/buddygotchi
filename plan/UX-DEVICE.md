# UX: The Device

Status: second draft, 2026-09-08. Refines `VISION.md` for the physical buddy.
Hardware is not decided, so this is written against a face canvas and an
input inventory, not a board.

Part I walks through the flows that matter. Part II is the reference for
the parts those flows are built from. If Part II ever needs something Part I
does not use, cut it from Part II.

---

## 0. The whole vocabulary on one card

Everything the device can do. If a feature does not fit here, it does not
ship.

| | |
| --- | --- |
| **States** (6) | Asleep · Idle · Working · Needs you · Done · Uh-oh |
| **Overlays** (2) | Greet · Boop |
| **Cheer sizes** (3) | Hop · Cheer · Dance |
| **Buttons** (2) | Primary = yes, boop · Secondary = no, look |
| **Motion** (3) | Poke/pet, shake, flip |
| **Surfaces** (3) | Face · One card · One bubble |
| **Postures** (3) | Desk · Perch · Travel |
| **Sounds** (7) | One motif per state that has one, plus the boop giggle |

The design rule behind the small set: **idle is simple, need is loud.** At
rest the buddy is one shape bobbing on a dark field. As the situation gets
more important the device adds layers in a fixed order: color, then motion,
then sound, then the card. Nothing skips a layer, and nothing uses a layer it
has not earned. A user can learn this in a day, and a developer can hold it
in their head.

| Layer | Idle | Working | Done | Needs you |
| --- | --- | --- | --- | --- |
| Color | dark | dark | green ripple | amber |
| Motion | bob | lean in, effort | hop / cheer / dance | turns to you, leans forward |
| Sound | none | none | blip / chirp / fanfare | "meep?" |
| Card | none | none | none (bubble on collect) | yes |

---

# Part I: Flows

## 1. Onboarding

Goal: from box to a named buddy that has cheered once, in under five
minutes, with the device doing something delightful at every step so the
setup never feels like setup.

| Step | On the device | In the app | What the user does |
| --- | --- | --- | --- |
| 1. Unbox | Dark. The buddy is asleep in the box. | | Lifts it out, presses the primary button. |
| 2. First wake | A dim, grey sleeping face fades in, breathing. It stirs. One eye opens, then the other. Two blinks. It sees you: eyes go wide, a squish, a big smile. Then it notices a small Bluetooth mark pulsing softly in one corner and looks at it, curious. Glances back at you, then at the mark again. About five seconds, skippable. | | Watches. This is the unboxing moment and must feel hand-finished. |
| 3. Pair | The buddy keeps glancing between you and the mark, hopeful. When the app finds it, the mark brightens to solid and the buddy hops: it noticed you. If the OS needs a pairing code it appears in the one card, and the buddy peeks at it too. | Installs, opens, finds the buddy, shows the same grey face on screen. | Confirms pairing. |
| 4. Connect an agent | Still grey, watching the app, curious. | One click per agent: Claude Code, Codex, Cursor. Each success gets a tiny hop on the device. | Clicks. |
| 5. First signal | The moment the first real agent event arrives, color arrives with it: a shimmer runs across the body and the buddy takes its first color. It has been alive since the box; now the agent has moved in. This is the moment the product is about. | "Heard from Claude Code!" | Runs anything in their agent. |
| 6. Name | Buddy shows its name in a bubble with a proud pose, once. | Name field. | Types a name. It is permanent. |
| 7. First cheer | The first completed turn gets a Cheer regardless of size, and a gold orb appears. Tap to collect; bubble: "first one." | Mirrors it. | Taps the primary button. Now they know the loop. |

Rules:

- No step shows a technical word on the device. Pairing is "it noticed
  you." Hooks are "connect." The Bluetooth mark is the one technical symbol
  allowed on the face, and only while unpaired.
- If pairing fails, the buddy just keeps glancing at the mark. The app
  explains; the device never does.
- The buddy is grey from first wake until the first agent signal. Color is
  the reward for connecting, and it is what makes step 5 land.
- The first cheer is deliberately oversized so the loop is taught by doing
  it once.

## 2. Boot up and shut down

The buddy is a creature, so power states are sleep states. It never shows a
boot screen or a shutdown message.

**Waking**

- Primary tap from off: eyes open, a stretch, then straight into whatever
  state the app sends. If the app is not there yet, idle with an occasional
  glance at the corner.
- Wake after a long time off: the Greet overlay (Part II §14), sized to the
  gap. Hours: a yawn. A day: "missed you" bubble and a squish. A week or
  more: the big version with mini hearts, and capped there.

**Going to sleep**

- Owner's usual stop hour passes with no agents: one bubble with the day's
  recap line from the app ("good day. 14 done."), then the buddy yawns,
  curls, and sleeps.
- Unplugged and pocketed: after thirty seconds still and dark, sleep.
- Flipped face-down: nap immediately. Flip back to wake.
- **Asleep is an animation, not a power state.** The sleeping face stays on
  at the lowest brightness, breathing slowly, with the occasional twitch.
  The buddy never turns its own screen off and never powers itself down.
  Only the shutdown hold does that. A sleeping buddy on a desk at night
  should look like a sleeping creature, not a dead gadget. The hardware
  document must budget for an all-night dim sleep frame on battery.

**Shutting down**

- Hold the secondary button. At one second the screen dims and the buddy
  closes one eye. Keep holding to three seconds: "night night" bubble, eyes
  close, screen off. Letting go early cancels with a blink.
- The staged hold is the only destructive gesture on the device, and it is
  the only one that requires visible commitment.
- Waking from shutdown is a tap. Everything the buddy knows is on the Mac,
  so a dead battery loses nothing but a nap.

**Charging**

- Plugging in: a small contented wiggle. A charge mark sits in one corner
  while the screen is on. Nothing else changes.

## 3. One agent: working, needs you, done

The core loop. Written as a timeline of one real task.

**3.1 Working**

The agent starts a turn. The buddy sits up from idle, looks down and a little
away as if at the work, and starts a slow lean-in. Field stays dark. No
sound. From across the room: "it's busy." If the agent introduces itself,
its name shows in a bubble once, with a small nod. That is the only time an
agent's name appears on the device.

As the task goes on, effort shows. The app scores effort from elapsed time,
retries, and errors, and the device renders it as a parameter:

| Effort | What changes |
| --- | --- |
| light | The lean-in and a focused look |
| hard | Brows furrow, a sweat drop appears |
| grinding | Sweat plus a small tremble, and the buddy grips the edge in perch |

That is the whole range. Working is where the buddy spends most of the day,
so it must be pleasant to have in the corner of your eye for an hour: slow,
breathing, never busy-looking in the fidgety sense.

**3.2 Needs you**

The agent asks for permission or a decision. This is the loudest the device
ever gets, and it gets there in the fixed layer order within half a second:

1. **Color.** Field goes amber.
2. **Motion.** The buddy turns to face you and leans forward, eyes wide.
3. **Sound.** One rising "meep?"
4. **Card.** Slides up over the lower canvas, eyes still visible above it:

   ```
   run a command
   deletes files in this folder
   ● careful
   tap · yes     hold · no
   ```

   Line one is the tool in plain words. Line two is the app's plain-English
   gloss. Line three is the stakes dot: calm, amber, or red.

You decide:

- Tap primary: approve. Hold primary one second: deny.
- A red-dot prompt needs a two-second hold to approve, and the card has to
  be on screen for a second before it arms. A tap just gets a small head
  shake.
- On press the card shows "sending…", then "yes!" or "okay" when the app
  confirms. "no link?" after three seconds without confirmation. A press
  never claims a delivery that did not happen.

If you do not decide, the buddy waits patiently. Three minutes later, one
soft "meep?" and a small lean. A red-dot prompt may buzz once more after
that. Nothing else, ever, and nothing at all during focus time. Each time
you dismiss without deciding, the next nudge is half as loud.

The moment the decision lands the card slides away, the field fades to
dark, and the buddy turns back to the work. Back to 3.1.

**3.3 Done**

The turn completes. The app picks a cheer size from the story it knows:

| Size | When | What happens |
| --- | --- | --- |
| **Hop** | A normal completion | Hop, arc eyes, one bright blip, faint green ripple. 1.5 s. |
| **Cheer** | Real effort: a long turn, retries, an error along the way | Hop and spin, confetti, two-note chirp, green ripple. 2.5 s. |
| **Dance** | Hard-won: many retries, a red streak ending, a long struggle | The full dance, confetti burst, blush, short fanfare. 4 s. |

Then, whatever the size, a small gold orb settles beside the face and
twinkles, and the buddy returns to idle with a faintly expectant look. From
across the room: "something finished." That is the come-back call. It stays
until you tap the primary button: the orb pops, the buddy giggle-squishes,
and the bubble shows the story line for four seconds:

- "ten tries. nice job on the tests."
- "green at last."
- "done: landing page copy."

Most completions in a day are Hops. A few are Cheers. A Dance is rare and
earned, so it still lands the fortieth time.

**3.4 When it goes wrong**

One state covers every kind of bad news, so the user learns one shape:
**Uh-oh.** Field dim red and breathing, buddy slumps, eyes down, one low
note. What differs is the bubble:

- A failed turn or broken build: "build failed."
- The app thinks the agent is looping: "might be going in circles."
- A rate limit: "hungry. back at 3:40."

Any button clears the bubble. The state clears on the next good signal.
The buddy is sad about the work. It never looks at you.

## 4. Several agents: the same flow

The rule from the vision: one creature. Three agents running is still one
buddy, and the flow above is unchanged. What adds is small and ambient.

**Working, several.** One small dot per active session drifts along the
bottom edge of the canvas. Up to four, then a "+" mark. The face does not
change because of the count. Effort is the highest of any session.

**Needs you, several.** Prompts queue oldest first. The card shows a small
"1 of 3" in its corner. Deciding one slides the next in. Nothing else
changes; it is still one card, one decision at a time, the same buttons.

**Done, several.** Completions do not stack up cheers. If two land within a
few seconds, the bigger one plays and the other is folded into it. One gold
orb, always. The bubble on collect lists the latest story line and a count if
there was more than one: "done: landing page copy · +1."

**Uh-oh, several.** One session failing while others work: the buddy shows
Uh-oh for a moment, then returns to Working with the session dot for that
one tinted red until it recovers. The user sees the whole day the same way
they would with one agent, with a little more life along the bottom edge.

What we deliberately do not do: split the face, show a list, show names on
the face, or make the buddy busier because more agents are busy. The app has
the per-session view for anyone who wants it.

---

# Part II: Reference

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
| Sparks | Celebration, affection | Six confetti dots, one pink heart, one gold orb |
| Accessories | Cosmetics | Small, above or beside the eyes, drawn in the eye ink, never over the eyes or the card |

Eyes are the anchor, centered and largest. Every part has a resting
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

Motion reactions in any state: shake gives three seconds of X-eyed wobble,
flip face-down naps. Both are suppressed while a prompt is on screen.

There is no separate thinking, stuck, hungry, focus, or link-lost state.
Thinking is Working. Stuck and hungry are Uh-oh with a bubble. Focus is a
small mark in one corner. Link lost is Idle glancing at a dim Bluetooth
mark in the corner, then Travel. Unpaired is the same mark, pulsing, with
the buddy looking at it hopefully.

## 9. The cheer and the gift

Sizes and triggers are in Part I §3.3. Manners:

- No cheer sound twice within ten seconds; the second plays silent.
- A cheer never plays over Needs you or Uh-oh. It waits, or is folded into
  the next.
- One gold orb. Newer replaces older. Survives dim and sleep, not reboot.
- The orb hides under a card and returns when the screen is free.
- Collect is primary tap when nothing else is pending. Bubble for four
  seconds with the story line from the app. The device never composes
  text.

## 10. The card

Revised 2026-09-09. There is one card. It is used for Needs you, for the
pairing code, and for firmware updates. Same position (lower third, eyes
visible above), same motion (rises from the bottom edge, settles, leaves
the same way), same type. Users learn one card.

**No box.** The card is not a bordered panel. It is two lines of text on
the black field under the face, with the field's amber wash as the only
frame. Proportional type, the bundled Korean-capable face; one size for
the tool name (medium weight) and one for the gloss (regular).

Needs you layout, top to bottom:

1. **Tool line.** Stakes dot, then the tool in plain words. `2 of 3` at
   the right edge when more than one is waiting.
2. **Gloss.** One line, two at most. The app truncates.
3. **Hold ring.** A thin ring at the lower right, empty while the card is
   unarmed (600 ms), then a full-brightness, 2 px ring in eye ink. While the primary button is
   held a 4 px arc in the same ink fills clockwise over the required hold (1 s, 2 s for careful)
   and completes with the decision. Release before full: it drains back.
   The ring is the only affordance on screen.

**Hints appear only when needed.** No text explains the buttons at first.
After five seconds without input, one quiet line appears below the
gloss: `tap · yes   hold · no` (or `hold 2s · yes   side · no` for
careful). It hides when any button is touched. The hint and `n of m` use
pure grey `animRGB(146,146,146)`, never a dim mix. The pairing and update
cards carry no hint at all.

Decision feedback replaces the card: `yes!` / `okay` in the tool-line
position for 1.5 s, then the face returns. `sending...` past 3 s of no
acknowledgement, `no link?` past 3 s more.

Nudge ladder, chosen by the app, rendered by the device:

| Rung | Default | Device |
| --- | --- | --- |
| 0 | On arrival | Amber, turn, one "meep?" |
| 1 | Three minutes | One soft "meep?", small lean |
| 2 | Red dot only, rate-limited | Stronger sound, brief field pulse |
| Focus | Declared | Rung 0 only, silent |

Dismissal halves the next rung. Three in a row auto-snoozes the class:
bubble "okay, I'll hush about that."

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
| **Primary** | Yes: approve → collect → clear Uh-oh bubble → boop | Quick command (connected) · stats (travel) | Deny (1 s, armed prompt) · approve red dot (2 s) · pet (otherwise) |
| **Secondary** | No: deny → dismiss → next stats card → "hmph" flick | | Focus toggle (1 s) · shutdown ladder (3 s) |

Primary tap resolves first match: armed prompt → gift → Uh-oh bubble →
boop. "Primary means yes" stays one verb.

Without a secondary button: deny stays on primary hold, focus is a triple
tap, stats page by repeated double tap, shutdown is a long primary hold with
the same staged feedback.

## 13. Travel mode and stats

Two cards, summoned by double tap or the secondary button, auto-dismiss in
ten seconds. Big type, one fact per line, no charts, safe to show anyone.

1. **The buddy.** Name, level, XP bar, streak with a small flame. The buddy
   stands beside it in its cosmetics and strikes a proud pose.
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
Page two: `12 days together`, `84 tasks`, the biggest moment in the
buddy's words, `today: 6`. Numbers are formatted with the app's
localizer; the device never composes sentences.

## 14. Rituals

- **First wake.** Part I §1. Asleep in the box, wakes, sees you, notices
  the Bluetooth mark; grey until the first agent signal brings color.
- **Greet.** Under an hour, a glance and smile. Hours, a stretch and yawn.
  A day, squish and "missed you." A week or more, the big version. Capped.
- **Level up.** A soft light sweeps across the eyes over 900 ms (never a
  bar through the face) and the whole field mixes toward the skin tint
  over 300 ms, then back over 300 ms, once;
  cosmetic reveal if any; one bubble with the level.
- **Streak milestone.** A flame pulse and a bubble. Never a reminder, never
  a comment when a streak breaks beyond a shrug.
- **Retire.** From the app. Slow fade to dark with a single blink.

## 15. Sound

Seven motifs and no more. Each under 700 ms, each
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

Manners: never two sounds within a second; no cheer sound twice in ten
seconds; three volume steps and mute, remembered on the device; **café
rule**: at the lowest step, audible at arm's length and inaudible at the
next table; silent in focus except rung 2 and Uh-oh; silent asleep.

## 16. Text, priority, dim

- Text lives in the card and the bubble. Bubbles are plain text in the eye
  ink beside the face, no pill and no box (8-bit fills read as mud), one
  line, two at most, four seconds or any button. The app truncates.
- The device font must render launch languages including Korean legibly.
- Screen priority, highest wins: system card → Needs you card → decision
  feedback → Uh-oh bubble → stats → bubble → overlay → face and orb. Lower
  layers keep simulating.
- Dim after two minutes idle; Asleep is the lowest brightness. The screen
  never turns itself off. A pending prompt never dims. An uncollected orb
  keeps a low glow.

## 17. Micro-idles

Only while Idle, at least ninety seconds apart, under two seconds each:
yawn, follow a session dot one lap, happy wiggle, one slow look at you,
head tilt. Perch adds a slow dangle of the gaze; Travel adds looking around the
room. Never within ten seconds of a real interaction.

## 18. Cosmetics

Colors and skins tint the field wash and the eye ink. Eye geometry never changes. Accessories are
small silhouettes drawn in the eye ink above or beside the eyes (a crown
sits above the gap between the eyes, a sprout leans from one side, a
scarf is a soft band below the mouth), never over eyes or card, never
outlined. Sounds swap the motif within the same manners. Silhouettes
change eye spacing and size at milestones within the same eye anchor.
Schedule is `UX-GROWTH.md`.

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
| Working | Eyes down-left, lean 5 px; hard adds the brow and the sweat drop (one drop slides 18 px every 3 s); grinding adds a faint tremble (±1.5 px). |
| Needs you | Eyes spring wide, tiny lean toward you. |
| Boop (tap, pet) | Eyes squish to 60% height for 250 ms and spring back; blush; smile; **one heart**: it pops in 12 px above the gap between the eyes (scale 0→1 in 150 ms, 6% overshoot, radius 10, pink), floats up 24 px over 900 ms, shrinks away in the last 100 ms. While held, a new heart every 900 ms. Never more than one on screen. |
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
| Gift orb | Bobs ±4 px; on collect it shrinks to nothing in 200 ms. |
| Card | Springs up, eases away. Unchanged. |
| Retire | Slow fade with one blink. Unchanged. |

## 19. Decisions this document needs

1. **Canvas shape.** Moves the card and bubble, changes how perch feet read.
2. **Second button.** Assumed yes; fallback in §12.
3. **Touch.** Assumed no.
4. **Agent name on the device.** Resolved: only in the one bubble when an
   agent introduces itself, never ambiently.
5. **Story-line length.** Forty characters assumed; the canvas and the
   Korean font decide.
