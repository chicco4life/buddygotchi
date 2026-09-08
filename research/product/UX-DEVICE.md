# UX: The Device

Status: first draft, 2026-09-08. Refines `VISION.md` §6 (postures), §7 (the
experience), §9 (personality and voice), and §14 (hardware principles) for
the physical buddy. Hardware is not decided, so this document is written
against a **face canvas** and an **input inventory**, not a board. It carries
forward the parts of `PEBBLE-UX.md` that were earned in the field and drops
the rest.

Companion documents: `UX-APP.md` (the Mac side of every flow here),
`UX-GROWTH.md` (what levels unlock), `UX-VOICE.md` (what the buddy says).

---

## 0. What this document assumes

The input inventory from the vision, and nothing more:

| Assumed | Notes |
| --- | --- |
| A color face canvas | Shape open (round, square, or wide). Every layout rule here is expressed as "center," "edge," and "corner" so it survives the choice. |
| One primary button | Tap, double tap, hold. The "yes" button. |
| One secondary button | Tap, hold. The "no / look" button. Marked optional in the vision; this document assumes it exists and notes what changes without it (§9). |
| A speaker | Chirps and digital sounds. No speech, no music. |
| Motion sensing | Pokes, shakes, flips, and orientation for posture. |
| A battery and a charge state | The device knows if it is on power. |
| Bluetooth to the Mac | Presence of the link is a first-class state. |
| Touch | Not assumed. If present, it is affection-only (§10). |

The device is a thin terminal. It renders a state the app sends, plays
sounds, and reports button and motion events. Everything below is what that
rendering must look and feel like.

---

## 1. Doctrine

Rules that every screen, animation, and sound must obey.

1. **At rest the screen is the face and nothing else.** No text, no
   counters, no status chrome. The creature is the interface.
2. **Light is spent on need.** The field behind the face is dark by default.
   It brightens only when a human is blocking something. Spending brightness
   on happy states would make it meaningless.
3. **Three tiers of information.** *Ambient*: shown through the body. *On
   request*: shown when you ask, then gone. *Demanded*: takes the screen,
   and only needs-you, error, and system flows may.
4. **Buttons are the only actuators.** Touch and motion are affection and
   display only. They can never approve, deny, or change persisted state.
5. **Urgency beats affection.** Affection overlays play on calm states only.
   Needs-you, error, and sleep always win.
6. **The cheer scales.** Most completions get a small, quick, lovely
   acknowledgment. Fanfare is reserved for hard-won moments, so it still
   means something the fortieth time.
7. **Nothing teleports, nothing blocks, everything breathes.** Every change
   is a transition. No frame is fully static while the screen is on.
8. **Text is a last resort,** and only inside a bubble or a card. Never bare
   on the face.
9. **One creature.** Several agents never produce several faces. The count
   is shown as a small ambient detail, never as a list.
10. **Posture-aware.** The same state has a desk version and a perch
    version. Neither is a downgrade.
11. **Feelings are about the work.** No expression the buddy makes is aimed
    at the owner. Sadness is about a red build. Sass is about the agent.
12. **Premium in every frame.** Easing, timing, and sound are finished, not
    placeholder. If a motion would look cheap on a phone, it is cheap here.

---

## 2. Anatomy of the creature

The face is built from parts that each carry expression, so states can be
composed rather than hand-drawn one by one.

| Part | Carries | Range |
| --- | --- | --- |
| **Eyes** | Attention, mood, energy | Open, half, closed, wide, arc (joy), X (dizzy), looking in any direction, blink |
| **Brows** | Effort, concern, surprise | Neutral, raised, furrowed, one raised |
| **Mouth** | Mood | Small neutral, smile, open smile, flat, small o, wobble |
| **Cheeks** | Affection, exertion | Blush, sweat drop |
| **Body** | Energy, posture | Bob, squish, lean, stretch, hop, wobble, curl |
| **Field** | Need | Dark, dim warm, amber, red pulse, green ripple |
| **Sparks** | Celebration, affection | Confetti, mini hearts, a single gold orb |
| **Feet** | Perch posture only | Dangle, kick, tuck |
| **Accessories** | Level cosmetics | Drawn on top, never occluding eyes |

Rules for the parts:

- Eyes are the anchor. They are centered on the canvas and larger than any
  other part. At two meters, the eyes and the field are all that reads.
- Every part has a resting micro-motion: eye drift, breathing bob, field
  breath. Nothing sits perfectly still.
- Expressions are blends. "Busy and a little worried" is busy eyes plus a
  slightly furrowed brow, not a separate sprite.
- The silhouette changes at a few level milestones (`UX-GROWTH.md`), but
  the eye positions do not, so every expression survives every silhouette.

---

## 3. States and how they look

The body layer. Each row is what the app can ask the device to render, and
what the device does with it. Effort and intensity are parameters, not
separate states.

| State | Eyes | Brows | Body | Field | Sound on entry |
| --- | --- | --- | --- | --- | --- |
| **Sleep** | Closed | Neutral | Slow deep breathing, occasional twitch | Dark | None |
| **Idle** | Open, drifting, blinking | Neutral | Gentle bob, micro-idles (§14) | Dark | None |
| **Busy** (effort light / normal / hard / grinding) | Looking down and slightly away, as if at work | Neutral → focused → furrowed | Bob → lean-in → lean-in with sweat drop → sweat plus small tremble | Dark | None; a soft tick every few minutes at grinding, optional |
| **Thinking** | Looking up and to one side | One raised | Still, slow sway | Dark | None |
| **Celebrate** (tier 0 to 3, §4) | Arc | Raised | Hop → hop plus spin → dance → full dance with confetti | Green ripple, scaled | Blip → chirp → trill → fanfare |
| **Error** | Half, looking down | Furrowed inward | Slump, slow | Dim red, breathing | One low note |
| **Stuck** | Looking side to side slowly | Furrowed | Small pacing sway | Dim warm | Two low notes, once |
| **Needs-you** | Wide, looking straight at you | Raised | Turns to face you, leans forward | Amber, steady | Rising two-note "meep?" |
| **Hungry** (rate limit) | Half, drooping | Neutral | Slower bob, occasional sag | Dark | One soft descending note |
| **Greet** | Wide then arc | Raised | Squish then bounce, scaled to absence | Dark | Cheerful two-note |
| **Affection** | Arc or closed-happy | Raised | Squish, mini hearts | Dark | Soft giggle blip |
| **Dizzy** | X | Raised | Wobble | Dark | Wobbly descending |
| **Focus** | Open, calm, half-lidded | Neutral | Very slow bob | Dark, with a small quiet mark in one corner | None |
| **Link lost** | Open, looking around | One raised | Small searching sway | Dark | One soft question note, once |

Notes:

- Busy is where the buddy spends most of its connected life, so its four
  effort levels get as much motion design as celebrate. Effort comes from
  the app (session length, retries, errors, agent self-report).
- Needs-you and error are the only states that brighten the field. Stuck
  and hungry use a dim warm field so they are noticeable at a glance but not
  a demand.
- Several agents: one small dot per active session sits along the bottom
  edge of the canvas, drifting slightly. Never more than five; the fifth
  becomes a "+" mark. The face never changes because of the count.

---

## 4. The cheer

The hero interaction. It happens dozens of times a day, so it is designed as
a system with tiers, not a single animation.

### 4.1 Tiers

| Tier | When | Motion | Field | Sound | Duration |
| --- | --- | --- | --- | --- | --- |
| **0 · Nod** | A turn ends with no task signal (a question answered, a small edit) | Eyes arc briefly, tiny bob | None | None | 0.6 s |
| **1 · Hop** | A task or turn completes normally | Hop, arc eyes, small sparkle | Faint green ripple | One bright blip | 1.5 s |
| **2 · Cheer** | Completion after real effort: a long turn, several retries, an error in the session | Hop plus spin, arc eyes, confetti | Green ripple | Two-note chirp | 2.5 s |
| **3 · Dance** | Hard-won: many retries, a long red streak ending, a task the buddy watched struggle for a long time | Full dance, confetti burst, blush | Green ripple twice | Short fanfare, four notes | 4 s |

The tier comes from the app, which knows the story (retries, elapsed time,
error count, the agent's own effort report). The device only renders it.

### 4.2 Rules that keep it lovely

- **Distribution matters.** In a normal auto-mode day, most completions
  should land at tier 0 or 1. Tier 2 a few times. Tier 3 once, maybe. If a
  day produces ten tier 3s, the thresholds are wrong.
- **Sound is capped by tier and by rate.** Tier 1 is a single blip because
  a trill at completion rate became noise in the field. No celebration sound
  plays twice within ten seconds; the second one is silent and visual only.
- **Cheers interrupt nothing that matters.** A cheer never plays over
  needs-you or error. It queues and plays when the screen is free, or it is
  dropped if superseded.
- **Every tier ends in the same place:** the persistent gift (§4.3).

### 4.3 The gift and the come-back call

After any tier 1 or above, a small gold orb settles near the face and
twinkles. The face returns to whatever it was doing (idle, or busy with the
next task) but carries a faintly expectant look. This is the come-back call
from the vision: from across the room, "something finished" is visible
without any text.

- **Collect** with a primary tap when no prompt or error is showing. The orb
  pops, the buddy giggle-squishes, and a bubble shows the story line for
  four seconds.
- **One orb.** A newer completion replaces the pending one. The app keeps
  the history; the device keeps only the latest.
- The orb survives dim and sleep. It does not survive a reboot.
- If a needs-you or error arrives while an orb is pending, the orb hides and
  returns when the screen is free.

### 4.4 The story line

The bubble on collect, and the line the buddy says on tier 2 and 3, come
from the app's learned context (`VISION.md` §9, "It learns you"). Examples of
the shape, each under 40 characters on the device:

- "ten tries. nice job on the tests."
- "green at last."
- "that one fought back."
- "done: landing page copy."

The device receives the line ready to render. It never composes text. Lines
longer than the bubble allows are truncated by the app before sending, never
by the device.

---

## 5. Needs-you

Rarer every month, still the most consequential thing the device does.

### 5.1 The card

When a prompt arrives the field goes amber, the buddy turns to face you and
leans forward, and a card slides up from the bottom edge over the lower part
of the canvas. The eyes stay visible above it.

The card has three lines:

1. **What.** The tool, in plain words. "Run a command," "Edit a file,"
   "Read your files," "Reach the internet."
2. **Gloss.** A plain-English line from the app about what this specific
   call does. "Deletes files in this folder." "Installs packages."
3. **Stakes.** One of three marks, from the app's risk read: a calm dot for
   *fine*, an amber dot for *check it*, a red dot for *careful*.

Below the card, the button hint: "tap · yes  hold · no." The hint is the one
place text appears outside a bubble, because the decision has to be
unambiguous.

### 5.2 The decision

- **Tap primary** approves once. **Hold primary for one second** denies.
- **Careful** prompts require a **two-second hold to approve** and show the
  gloss for at least a second before the button arms. A tap does nothing but
  a small head shake.
- The prompt arms only after a short delay from arrival, and a press that
  woke the screen never counts. A decision requires a mechanical press.
- On press: "sending…" until the app confirms, then "yes!" or "okay." If no
  confirmation arrives in three seconds: "no link?" A press never claims a
  delivery that did not happen.
- The same prompt is visible in the app; whichever side decides first wins,
  and the other side clears.

### 5.3 The nudge ladder

The device does not decide when to nudge. It renders the rung the app
chooses.

| Rung | Default timing | Device behavior |
| --- | --- | --- |
| 0 · Ambient | On arrival | Amber field, face turned, one "meep?" |
| 1 · Chirp | After three minutes unacknowledged | One soft repeat of "meep?", small lean |
| 2 · Buzz | High stakes only, rate-limited | A stronger sound and a brief field pulse |
| Focus | Declared focus time | Rung 0 only, silent |

Each dismissal halves the next rung's intensity for that class in the
session. Three dismissals in a row auto-snoozes the class and the buddy says
so in a bubble: "okay, I'll hush about that."

### 5.4 Several prompts

Oldest first. A small count sits on the card ("1 of 3"). Deciding one slides
the next in.

---

## 6. Error, stuck, and hungry

Three states that mean "something is off," kept distinct on purpose.

- **Error** is a fact from the agent: a turn failed, a build broke. The
  field goes dim red and breathes. A card shows one line of what happened
  ("build failed" or the agent's error class) and clears on any button or on
  the next successful signal. The buddy slumps but never looks at you.
- **Stuck** is the app's inference: the same thing tried repeatedly, or a
  long silence mid-task. Dim warm field, pacing sway, two low notes once.
  Bubble: "it might be going in circles." Clears on the next distinct
  progress signal. Tuned to be quiet; a false stuck is worse than a missed
  one.
- **Hungry** is a rate limit. No field change, just a drooping, slower
  buddy and one soft note. Bubble on request: "hungry. back at 3:40." The
  time comes from the app when the agent reports it. Hungry never nags.

---

## 7. Postures

The device reads its own orientation and, where the hardware allows, the
mount. The app can also set the posture explicitly. Each connected state has
two renderings.

### 7.1 Desk

The default set described in §3. The buddy faces the owner, sits upright,
and bobs in place. It stands on the desk and behaves like it has a floor.

### 7.2 Perch

The buddy is on the top corner of the laptop lid, above the screen, looking
down at the work. The animation set is redrawn around that fact.

| State | Perch version |
| --- | --- |
| Idle | Sits on the edge, feet dangling and kicking slowly, gazes down at the screen, occasionally looks up at you |
| Busy | Leans over the edge to watch the work, feet tucked; at hard effort it grips the edge |
| Thinking | Looks up and away from the screen, one foot swinging |
| Celebrate | Hops on the spot on the corner, feet kicking; tier 3 adds a little jump-and-land with a wobble |
| Needs-you | Peers over the edge straight down at you, then tips its head |
| Error | Sags, feet stop kicking, looks down at the screen |
| Stuck | Shuffles side to side along the edge |
| Sleep | Curls up in the corner |
| Greet | Pops up over the edge like it was hiding |

Perch mode is the posture most seen by other people, so its idle set is the
richest. The buddy in perch is a small ad every time someone glances at the
laptop.

### 7.3 Detecting posture

- Upright and stationary on a flat surface: desk.
- Tilted to the lid angle and held there: perch. Where the mount can signal
  its presence, that wins.
- Moving, or face-down, or no link for more than a minute while on battery:
  travel.
- Ambiguous: keep the last posture. Never flicker between sets.

---

## 8. Travel mode

Unplugged and unlinked. The buddy is a creature you carry, poke, and show to
people. It has no live events and does not pretend to.

### 8.1 Entering and leaving

- Link lost while on battery: after a minute of searching, the buddy yawns
  and settles into travel idle. No "disconnected" text, ever.
- Pocketed (dark, still): sleeps within thirty seconds. Wakes on pick-up or
  a button.
- Reconnected: the greet ritual (§15), sized to time away.

### 8.2 Travel idle

The same idle as desk, with two differences: micro-idles are more frequent
(the buddy has nothing else to do), and a small battery mark sits in one
corner when below a quarter.

### 8.3 Poking, shaking, flipping

| Input | Response |
| --- | --- |
| Primary tap | Boop: squish, blush, giggle blip |
| Primary hold | Pet: sustained affection, mini hearts, for as long as held |
| Double tap primary | Show stats (§8.4) |
| Shake | Dizzy for three seconds |
| Flip face-down | Nap; screen off, wakes on flip back |
| Pick up | Perks up, looks around |
| Secondary tap | Stats page (same as double tap), or next page if already showing |

### 8.4 Stats pages

The one place the device shows numbers. Summoned, never ambient, and
auto-dismiss after ten seconds. Designed to be handed to a friend.

1. **Card one, the buddy.** Name, level, and the XP bar with the number to
   the next level. The buddy stands beside it in its current cosmetics.
2. **Card two, the streak.** Current streak with a small flame, best
   streak, rest days banked.
3. **Card three, today.** Turns, tasks, cheers, hours. From the last sync;
   dated if older than a day.
4. **Card four, lifetime.** Days together, tasks, biggest cheer, the agent
   it has seen most.

Rules:

- Big type, one fact per line, no charts. Legible from arm's length in
  daylight.
- The buddy reacts to its own stats: a proud pose on the level card, a
  small flex on a long streak.
- Nothing about the owner's projects or habits appears here. Stats pages are
  safe to show anyone.

### 8.5 Showing a friend

The design intent for travel mode is "look at this." Every travel
interaction should be satisfying to demonstrate in five seconds: poke it,
shake it, show the level. There is no menu to navigate and no setting to
find. Comparing two buddies device-to-device is an open idea (vision §18).

---

## 9. Button grammar

| | Tap | Double tap | Hold |
| --- | --- | --- | --- |
| **Primary** | Context yes: approve → collect gift → acknowledge error → dismiss card → boop | Quick command (connected) or stats (travel) | Deny (armed prompt, one second) → approve careful prompt (two seconds) → pet (otherwise) |
| **Secondary** | Context no: deny (armed prompt) → dismiss → next stats page → small "hmph" flick | — | Focus mode toggle (one second); further hold ladder to screen-off and power-down |

Resolution order for the primary tap, first match wins: armed prompt →
pending gift → displayed error → open card → plain boop. "Primary means yes"
must stay a single reliable verb.

Power-down is a staged hold on the secondary button, with a visible "night
night" before the final stage, so the destructive end requires commitment.
Waking is always a tap.

**Without a secondary button:** deny stays on primary hold, focus moves to a
triple tap, stats paging becomes repeated double tap, and power-down becomes
a long primary hold with the same staged feedback. Everything remains
reachable; the document prefers two buttons because "yes" and "no" on
separate keys is easier to trust.

---

## 10. Motion and touch

Affection and display only. Never a decision.

- Shake, flip, and pick-up behave the same in every mode.
- Shake and nap are suppressed while a prompt is armed. Nothing may obscure
  a decision the human owes.
- If the hardware has touch: tap is a boop, stroke is a pet, and stroking a
  sleeping buddy gives a one-eye peek without waking it. Touch is ignored
  during nap so a bag cannot boop it.
- Motion is also how posture is detected (§7.3), which is display-only by
  definition.

---

## 11. Sound

A speaker, a small vocabulary, strict manners.

### 11.1 Families

| Family | Character | Used for |
| --- | --- | --- |
| **Blips** | Single bright notes, under 120 ms | Tier 1 cheer, boop, collect |
| **Chirps** | Two or three notes, under 300 ms | Needs-you, greet, tier 2 cheer |
| **Trills and fanfare** | Four notes, under 700 ms | Tier 3 only |
| **Lows** | Single or double low notes | Error, stuck, hungry |
| **Textures** | Very quiet ticks and sighs | Grinding effort (optional), yawns |

Every event has exactly one motif. Each motif must be tellable from the
others across a room with eyes closed.

### 11.2 Manners

- Never two sounds within a second. The later one is dropped.
- No celebration sound twice within ten seconds.
- Needs-you repeats at most on the nudge ladder, never on its own.
- Volume has three steps and mute, set on the device or in the app. The
  device remembers its own setting.
- **Café rule:** at the lowest step every sound is audible at arm's length
  and inaudible at the next table.
- Silent during focus mode except rung 2 nudges and errors.
- Sleep and travel-sleep are silent.

### 11.3 Voice

The buddy does not speak. Its lines are text in bubbles. Sound and text
arrive together on tier 2 and 3 cheers and on greets, so the chirp is the
"voice" and the bubble is the words.

---

## 12. Text on the device

- Only in bubbles and cards. Bubbles sit beside the face, never over the
  eyes.
- One line, then two at most. The app truncates; the device never wraps
  more than two lines.
- Bubbles last four seconds, or until any button. A new bubble replaces the
  old one with a crossfade.
- Languages: the device font must render the launch languages, including
  Korean, at a legible size. This is a hardware and firmware constraint
  called out early on purpose.
- No text in caps, no exclamation marks except from the buddy's own voice
  in a cheer.

---

## 13. Screen priority

Highest wins. Lower layers keep simulating so nothing snaps when an overlay
clears.

| Priority | Layer |
| --- | --- |
| 1 | System takeovers: firmware update, pairing code |
| 2 | Needs-you card |
| 3 | Decision feedback ("sending…", "yes!", "okay", "no link?") |
| 4 | Error card |
| 5 | Stats pages (travel) or on-request cards |
| 6 | Bubbles |
| 7 | Affection overlay |
| 8 | Face, field, session dots, gift orb |

Orthogonal: dim and screen-off ladder, sleep, posture set.

Dim ladder: full brightness on any event, dim after two minutes idle, off
after ten on battery or thirty on power. A pending prompt never dims. An
uncollected gift keeps a low glow on the orb even when dim.

---

## 14. Micro-idles

Rare, randomized, only while idle. Minimum ninety seconds apart, each under
two seconds:

1. Big yawn.
2. Eyes follow a session dot one full lap.
3. Happy wiggle.
4. One slow direct look at you, single blink.
5. Head tilt, springs back.
6. Perch only: kicks feet a little faster, or peeks over the edge.
7. Travel only: looks around the room.

Never during busy, needs-you, or error. Never within ten seconds of a real
interaction. Rarity is the charm.

---

## 15. Rituals

Moments that happen once or rarely, and have to feel hand-finished.

- **Hatch.** First ever boot: an egg on black rocks, cracks, bursts into a
  blinking newborn face, and settles into a "pair me" look. About six
  seconds, skippable by any button. The app completes the hatch when the
  first agent event arrives; the device shows the newborn until then.
- **Naming.** Done in the app. The device shows the name in a bubble once,
  with a proud pose, then never shows it ambiently again.
- **Greet.** First link after time away: under an hour, a glance and a
  smile; hours, a stretch and yawn; a day or more, a squish-bounce and a
  "missed you" bubble; a week or more, the big version with mini hearts.
  Capped there. A month away is a big hug, never a guilt trip.
- **Unplug and pocket.** Yawn, curl, dark. Under two seconds.
- **Level up.** A short shimmer across the body, a new-cosmetic reveal if
  there is one, and a bubble with the level. Once, then the stats card is
  where it lives.
- **Streak milestone.** A small flame pulse and a bubble. Never a reminder
  the day before, never a comment when a streak breaks beyond a shrug.
- **Retire.** Done in the app. The device shows a slow fade to a dark
  screen with a single blink. Nothing else.

---

## 16. Cosmetics

How unlocks render. What unlocks when is `UX-GROWTH.md`.

- **Colors and skins** recolor the body and field tint. Eye and brow
  geometry never change, so every expression survives every skin.
- **Accessories** draw on top and never occlude the eyes or the card area.
- **Sounds** swap the motif for a family, never the manners.
- **Silhouettes** at a few milestones change body shape and size within the
  same eye anchor. A silhouette is visible from across a room; that is its
  purpose.
- Cosmetic changes happen at level-up in the app and appear on the device
  on the next sync, with the level-up ritual.

---

## 17. Presence and link

| Situation | Device |
| --- | --- |
| Paired, app running, agent active | Connected mode, live states |
| Paired, app running, no agents | Idle, then sleep after the owner's usual stop hour |
| Paired, app closed | After a minute: "link lost" look, then travel idle if on battery, sleep if on power |
| Not paired | "Pair me" look: hopeful face, eyes on the corner where the app would be |
| Charging | A small charge mark in one corner when the screen is on, nothing else |

The buddy never shows "disconnected," "no signal," or any technical word. It
shows what a creature would do: look around, settle, sleep.

---

## 18. Decisions this document needs

Ranked by how much they change the drawings.

1. **Canvas shape.** Round versus rectangular changes where the card and
   bubbles live and how the perch feet read. Everything else survives.
2. **Second button.** Assumed yes. If no, §9 has the fallback.
3. **Touch.** Assumed no. If yes, §10 covers it and pet becomes stroke.
4. **Whether the device ever shows the agent's name.** Currently no, except
   in a greet bubble when an agent introduces itself. The agent channel
   (vision §9) may want a small identity mark; leaning no on the device,
   yes in the app.
5. **Story-line length.** Forty characters assumed. The canvas and the
   Korean font decide the real number.

---

## 19. Not in this document

The app side of every flow, the exact XP and cosmetic schedule, the
buddy's lines, the risk classifier behind the stakes read, and anything
about boards, batteries, or mounts.
