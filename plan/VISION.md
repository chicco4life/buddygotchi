# Boop Vision

Status: v1 product vision, clean slate. Drafted 2026-09-07, revised same day.
This document is the top of a stack. It says what Boop is, who it is for, and
what it must feel like. Follow-on UI/UX documents (§19) refine each surface.
Where it conflicts with the archived `PRODUCT.md`, `MARKETING.md`, or `PEBBLE-UX.md` (now under `archived/research/product/`), this
document wins.

Everything described here is launch scope. There is no v1.5 list. If a
mechanism is in this document, it ships with the first buddy.

---

## 1. One line

**Boop is a small, cute creature that is the physical body of your AI coding
agent.** It sits by your side, works alongside your agent, cheers when the
work lands, slumps when it fails, and grows with you as you become more
technical.

North star: a person who is new to building software keeps Boop on their desk
every working day for a year, and describes it to a friend as "my buddy."

The hero moment is the **completion cheer**. Agents increasingly run on their
own in auto mode; the human sets a goal, waits, and comes back. The thing a
person feels many times a day is "it finished," and Boop makes that a small
celebration you can see across the room. Approval prompts and stuck agents are
real but shrinking. Boop handles them well without being built around them.

---

## 2. Who it is for

### The buyer

People who got into building software through AI agents and are becoming more
technical because of it. They run Claude Code, Codex, or Cursor, mostly in
auto mode. They are not "engineers" by identity, and they may never be. They
are shipping things they could not have shipped two years ago, and they are a
little anxious about what the agent is doing while they wait.

What they want from Boop, in their words:

- "Tell me when it's done. I keep drifting off and losing twenty minutes."
- "Make waiting feel less lonely and less stressful."
- "Let me show it off."
- "Tell me when something's actually wrong."

Identity purchase: *I am becoming someone who builds things, and this is my
companion on the way.*

### Who it is not for

Hardcore engineers who want deep customization. They will build their own,
they are a small audience, and their needs pull the product toward a
dashboard. If they buy it anyway, great, but nothing in the design serves them
at the expense of a newcomer.

### Expansion audience

Anyone who runs agents for work, not just for code. The state vocabulary
(asleep, idle, working, needs you, done, uh-oh) is not code-specific. Coding
agents are the beachhead because that is where the signal exists today.

### Launch constraints

- Signal sources at launch: Claude Code, Codex, Cursor, through their local
  hooks. Browser-based builders are out of scope for v1 and named as a later
  expansion.
- macOS only at launch.
- The software is free forever. The hardware is the product.

---

## 3. What it is

Three parts that must feel like one creature.

1. **The buddy** (hardware). A pocketable creature with a face, a speaker,
   a button or two, motion sensing, a battery good for a working day, and
   Bluetooth. It reads as a designed object, not a dev board. **The buddy is
   the creature.** There is exactly one creature per device, and its identity
   is tied to that device.
2. **The app** (free macOS app). The brain and the mirror. Watches your
   agents, keeps the buddy's personality and memory, runs the small local
   language model that gives the buddy its voice, and shows the same creature
   in the menu bar so you can see it when the hardware is in your bag.
   Without hardware the app still works and still shows a creature, but that
   creature is a preview, not a buddy. It has no level and cannot rank.
3. **The agent link.** Agents connect to the buddy in two ways. Their
   lifecycle events drive the buddy's body language automatically. And an
   agent can deliberately express itself through the buddy (a mood, a short
   line, a doodle) inside a sandbox the buddy controls.

The formula for "physical embodiment of your agent," which §9 expands:

- The **body** is driven by agent state. Always on, deterministic, no model.
- The **voice** is the buddy's own. A local model on the Mac, shaped by a
  personality that accrues from how you and your agents work together.
- The **channel** is the agent speaking through the buddy. Rare, opt-in for
  the agent, visually distinct, never able to override the body.

One creature, even with several agents running. The buddy never splits into
a fleet view. It is one body that all your agents share.

---

## 4. Principles

These are the tests every later decision must pass.

1. **Fully useful on day one.** Cheers, nudges, approvals, status, talking,
   and every posture work from the first pairing. All behaviors and cosmetics
   are available immediately. XP and levels are for bragging rights only.
2. **Cute first, useful second, never a dashboard.** If a screen of numbers
   would do the job better, Boop should not do that job. Stats live in the
   app and in travel mode where they are a trophy, not a workload.
3. **Feelings are about the work, never about the user.** The buddy is sad
   when a build fails and thrilled when tests pass. It is never disappointed
   in you, never guilts you, and never scolds. Sass, when it appears, is aimed
   at the agent or the world.
4. **Premium feel everywhere in software.** Motion, sound, typography, and
   copy in the app and on the device must feel considered and finished. The
   hardware cost is unknown; the software must feel expensive regardless.
5. **Fail open, fail cute.** If Boop is off, agents behave exactly as they
   would without it. If a link breaks, the buddy shows it in character.
6. **Local only, and see-extract-forget.** Agent events, memory,
   personality, and the voice model all run on the Mac. Nothing leaves the
   machine except an opt-in, pseudonymous leaderboard score (§10.6). The
   buddy sees the stream of what your agents do in order to learn from it,
   but it keeps only the small facts it extracts. It never stores
   transcripts, code, file contents, or prompt text, and everything it has
   learned can be cleared at any time.
7. **Scoring is public, simple, and understandable.** Anyone can read how XP
   works in one screen. Anti-farming is best effort, never at the cost of
   clarity.
8. **The user always knows who is speaking.** The buddy's own voice and an
   agent speaking through it are visually disjoint.
9. **No silent behavior changes.** If an update changes how the buddy acts,
   the buddy says so.

---

## 5. What Boop is not

Non-goals, so later documents can cite them.

- **Not a productivity device.** It does not measure you, score your output,
  or optimize your day. It is not competing with keyboard-shaped agent
  controllers or dashboards, and it should never be reviewed against them.
- **Not just a toy.** It knows what your agents are doing and it acts on it.
  A desk toy that ignores the work is a different product.
- **Not a chat interface to the agent.** You talk to your agent through your
  agent. The buddy reacts, comments, and relays a few quick commands. It is
  not a second place to type prompts.
- **Not a fleet console.** Several agents, one creature, always.
- **Not a notification center.** It never shows a list of things to dismiss.
- **Not a judge.** It has no opinion on your code, your choices, or your
  hours.

---

## 6. Three postures, two modes

Boop lives in three physical postures. Two of them are connected; one is not.

| Posture | Where | Link | What the buddy does |
| --- | --- | --- | --- |
| **Desk** | On the desk beside the keyboard, usually on power | Bluetooth to the Mac | Full companion: cheers, nudges, approvals, voice. Faces you. |
| **Perch** | Clipped to the top corner of the laptop lid, on battery | Bluetooth to the Mac | Full companion in a different body language. It sits on the edge of your screen and looks down at your work, leans in when the agent is busy, peers over the edge when it needs you, dangles its feet when idle, and does a little hop on the corner when the work lands. |
| **Travel** | In a bag or pocket, in your hand at a café | None | Offline creature: reacts to pokes, shakes, and flips; shows its level, streak, and stats; plays idle animations; is the thing you hand to a friend. |

Desk and perch are the same **connected mode** with a posture-aware animation
set. The buddy knows which posture it is in from its orientation sensor and the
mount, and plays the matching set. Travel is **offline mode**.

Transitions are moments, not settings:

- Unplug and pocket it: it yawns and curls up. Stats from the day are carried
  with it.
- Pull it out on the train: it wakes, stretches, shows its level and the
  day's tally if you ask.
- Reconnect at the desk: a greeting scaled to how long you were gone. Never a
  guilt trip.

Perch mode gets its own animation vocabulary because it is the posture most
likely to be seen by other people. It is the ad.

---

## 7. The experience, moment by moment

### Day one

Open the box, the buddy is asleep. Press the button and it wakes for the
first time, sees you, and notices the Bluetooth mark it needs you to answer.
Open the app, it walks you through connecting Claude Code, Codex, or Cursor
with one click each. The buddy is grey until the first time the app hears an
agent; then color runs across it. The agent has moved in. That is the first
celebration and the first shareable moment.

You name it. The name is permanent (§11).

### A working session

- Agent starts: the buddy perks up, and greets the agent by name if the agent
  introduces itself.
- Agent is working: the buddy is busy alongside it. Effort shows on its face.
  A long, error-pocked task makes it sweat; a quick one is a light trot.
- Several agents at once: the buddy stays one creature and shows a small
  count. It never becomes a fleet dashboard.

### The work lands (the hero moment)

A turn completes, tests pass, a task finishes: the buddy cheers, scaled to
how hard the task was. Big struggle, big celebration. A one-minute task gets a
hop; an hour of errors and retries gets the full dance and a chirp you can
hear from the kitchen.

The cheer knows the story. If that turn was the tenth attempt at the same
test, the buddy says so. If the build had been red all afternoon, going green
is a bigger deal than green after green. What the buddy has learned about the
project and about you (§9) turns a generic cheer into a specific one.

The cheer persists until you boop it. That is the come-back call: a task that
finished while you were reading something else still pulls you back, without
a notification to dismiss. In a day of auto-mode work this is most of what
the buddy does, and it has to be good enough to enjoy the fortieth time.

### The work fails

Build breaks, agent errors, rate limit hit: the buddy slumps. It is sad about
the work, sometimes wry about the agent, never about you. It recovers on the
next signal.

### The agent is stuck

Repeated tool calls with similar arguments, repeated errors, or a long silence
mid-task: the buddy notices and says so, in the same "uh-oh" shape it uses
for errors, with a different line. This will be rare, and when it
happens it is real. Newcomers do not recognize a stuck loop; the buddy does.

### The agent needs you

Rarer every month as auto mode spreads, but still real: a permission prompt,
a question, a credential. The buddy turns to face you, glows amber, and chirps
once. On the face: the tool, a plain-English gloss of what the agent wants
("wants to delete files in this folder"), and a stakes read (fine / check it
/ careful). If you do not respond, it escalates gently: a second chirp after
a few minutes, a buzz only for high stakes, never during declared focus time,
and each dismissal halves the next nudge.

Press to approve, hold to deny. High-stakes prompts require a longer hold and
show the gloss first. The same prompt is in the app and mirrors the decision.

### End of day

When your usual stop hour passes, the buddy winds down and offers a recap in
its own voice: what the agents did, what shipped, what is still open, what it
noticed. One screen in the app, one line on the device. Then it sleeps,
visibly: a breathing face at the lowest brightness, never a blank screen. It
does not power itself down.

### Away

Close the laptop: the buddy sleeps. Come back after days: a greeting sized to
the gap. Streaks are tracked (§10.4), but the buddy's body never regresses.

---

## 8. How it helps

The utility layer. All of it is available at level one. Listed in order of
how often a newcomer in auto mode will feel it.

1. **Come-back call.** A finished task keeps the buddy celebrating until
   acknowledged, so asynchronous work does not get lost.
2. **Daily recap** in the buddy's voice.
3. **Spend and rate-limit awareness.** Where the agent exposes it, the buddy
   shows how far through a usage window you are, in creature terms
   (full, peckish, hungry) with the real number in the app.
4. **Stuck detection.** Repeated tool calls with similar arguments, repeated
   errors, or a long silence get surfaced as "it might be going in circles."
5. **Focus mode.** One button hold silences everything except high stakes.
6. **Needs-you alerts** with a gentle nudge ladder and focus hours.
7. **Plain-English risk translation** on approval prompts. Newcomers do not
   know what a shell command does. The buddy tells them what it will touch and
   how reversible it is.
8. **Quick commands.** A double press sends a prompt you set ("continue",
   "run the tests", "summarize what you did").
9. **Teach moments.** When an agent uses a tool the user has never seen, the
   buddy offers a one-line explanation in the app. Opt-out per topic.

There is no voice input. The buddy has a speaker, not a microphone, and the
user talks to agents through the agents.

Explicitly not a helper: reviewing code, judging quality, or measuring the
user's productivity.

---

## 9. Personality and voice

### The body (deterministic)

Agent events map to a small fixed vocabulary: six states (asleep, idle,
working, needs you, done, uh-oh) and two overlays (greet, boop). Effort and
cheer size are parameters on working and done, not extra states. The set is
deliberately small so a user can learn it in a day; the full grammar is in
`UX-DEVICE.md`. This layer never needs a model and works identically for
every agent. It is the floor.

### The voice (local model)

A small language model on the Mac writes the buddy's short lines: greetings,
reactions, quips about the agent, the recap. It must be small enough to run
on most Macs people actually own, and fast enough that a line lands inside a
second. Model choice is an engineering decision. It is conditioned on:

- a **personality** made of a few slow-moving traits (energy, cheek, warmth,
  curiosity) that drift with how you work: hours, tool mix, outcomes, how you
  respond to nudges, how often you boop it;
- what it has **learned** about you and your work (§10);
- the current event and time of day.

Rules for the voice:

- Short. One line on the device, a paragraph at most in the app.
- Sass has a ceiling and a target. It teases the agent, never the user.
- Setup asks one temperament question (earnest to cheeky). That is the
  starting point, not a persona mode. Two buddies with the same start diverge
  because their owners differ.
- Lines are generated on the Mac and sent to the device. The device never
  runs a model.
- Authored lines are the fallback when the model is unavailable or slow, and
  the only source on Macs that cannot run the model well.

Talking is a day-one feature. Levels widen the emotional range and the
vocabulary; they do not switch talking on.

The buddy speaks the owner's language. Multiple languages are launch scope,
which constrains the model choice and means the authored fallback lines are
written per language, not translated. Which languages ship first is open
(§18); Korean and English are the working assumption given where the product
is being tested.

### It learns you

The buddy gets to know you the way a friend at the next desk would: by being
there, noticing, and remembering a little. Over weeks it builds a small
picture on three fronts.

- **Your projects.** What they are, which one you are in, what you keep
  fighting with in each, when you last touched it, what shipped.
- **You.** Your hours, your rituals (tests first, commits often), the tools
  and agents you reach for, the things you have said you like or hate.
- **Your goals and habits.** What you are trying to get done this week, the
  streaks you are on, the patterns that repeat.

It uses this to say the right thing at the right time. The test that finally
passes on the tenth try gets a bigger cheer and "ten tries, nice job on the
tests." A project you have not opened in three weeks gets "oh, the landing
page, back at it?" A late night gets "we're close, right?" Never analysis,
never a report, one short line from a friend who was paying attention.

How it learns, at the level this document cares about:

- It watches the same hook stream that drives its body: prompts, tool calls,
  results, the agent's closing message. All of it is parsed on the Mac the
  moment it arrives and turned into small structured facts. The raw stream
  is discarded. We never write a second copy of a transcript.
- What it keeps is the extracted, higher-level stuff: "tests in this project
  took ten tries today," "works Sunday mornings," "dislikes writing regex."
  Human-readable lines, not data.
- A nightly pass, when the Mac is plugged in and idle, turns the day's facts
  into a few durable lines and nudges personality traits by small amounts.
- Everything it knows is on one page in the app, readable line by line, and
  any line or all of it can be cleared at any time. Clearing is a normal
  action, not a reset; the buddy keeps its name, level, and bond.
- It uses what it knows sparingly. A friend who mentions your habits every
  hour is not a friend.

Working notes and the sourcing behind this are in `IDEAS.md`, idea 1.

### The channel (agents speaking through the buddy)

An agent may, through a small tool interface, ask the buddy to show a mood,
say a short line, introduce itself, report how hard the task is, or leave a
doodle. Constraints the buddy enforces, not the agent:

- Suppressed while any prompt is pending. Urgency beats expression.
- Enum-only moods, byte-capped text, rate-limited.
- Rendered in a visibly different frame from the buddy's own voice.
- Never affects XP, streaks, or personality traits directly.

The buddy remembers agents by name. Over months, it has opinions about them.

### Sound

A speaker with a small library of chirps and digital sounds. No music, no
speech. Every state that asks for attention has one sound; idle, working,
and asleep are silent. Every sound is short enough not to annoy a café. The completion chirp is the most-heard sound in the product and
gets the most design attention. Volume and mute are on the device and in the
app.

---

## 10. Growth

Growth is the retention mechanic. It must be legible, earnable by anyone who
shows up, and simple enough to explain on one screen.

### 10.1 Level and XP (visible)

The buddy has a level and an XP bar, shown on the device in travel mode and in
the app always. The XP formula is public and short. Sources, in order of
weight:

| Source | Why |
| --- | --- |
| Turns completed | The unit of work the buddy cheers for. The core signal. |
| Tasks finished (a session that ends with completed work) | Outcomes. |
| Active days and streaks | Showing up. |
| Session length and tool calls | Effort, as a heuristic. |
| Tokens used, where the agent exposes them | Volume, small weight, best effort. |
| Check-ins (boops, pets) | Bond. |

No daily caps. The formula is a weighted sum that a user can read and
verify against their own day.

Never a source of XP: approving or denying prompts. A pet that gets happier
when you say yes is a rubber-stamp machine, and it is trivially farmable.

Anti-farming is best effort and never obscures the formula:

- the device signs its XP with a per-unit key, so software-only or spoofed
  scores cannot rank;
- events must arrive through real hooks from a real agent process the app
  can see;
- plausibility limits reject rates no human workflow produces, and the app
  says so rather than silently dropping;
- the leaderboard shows the buddy, not the person, so the incentive to cheat
  is small.

### 10.2 Usage signals we can get today

Grounded in the current hook integrations and local logs on a real machine.

| Signal | Claude Code | Codex | Cursor |
| --- | --- | --- | --- |
| Session start / end | hooks | hooks | hooks |
| Turn start / end | hooks (prompt submit, stop) | hooks (stop, with turn id) | hooks (stop) |
| Tool calls | hooks | hooks | hooks |
| Approval prompts | hooks | hooks | hooks |
| Errors and rate limits | hook (stop failure carries the error type, including rate limit) | partial | partial |
| Tokens | yes: hook payloads include the transcript path, and the transcript records per-message input, output, and cache tokens | yes: session logs record running token totals | no |
| Task completion | inferred from a turn ending without error | inferred | inferred |

So turns, sessions, tool calls, and active days are universal. Tokens are
available for Claude Code and Codex by reading local files the agent already
writes, and absent for Cursor. The XP formula leans on the universal signals
and treats tokens as a bonus, so a Cursor-only user is not disadvantaged.

### 10.3 XP does not unlock anything

Owner decision, 2026-09-10: keep progression and behavior separate. XP, levels,
streaks and keepsakes commemorate time and work together. They do not grant
animations, emotions, cosmetics, sounds, vocabulary, memory or capabilities.
Every implemented behavior and supported appearance is available from day one.
Level-up visuals may acknowledge a milestone without changing access.

### 10.4 Streaks

Streaks count consecutive active days and feed the XP formula. Rules that
keep them from becoming guilt:

- Losing a streak resets the counter and nothing else. The buddy does not
  get sad, shrink, or comment beyond a shrug.
- One free rest day per week is banked automatically, so a weekend off does
  not break a streak.
- Streak milestones are celebrations, not obligations.

### 10.5 Hidden bond

Separate from XP, the buddy has a bond that only goes up. It drives greetings,
warmth, and how much the buddy remembers. It has no number and no bar. It is
discovered, not tracked.

### 10.6 Global leaderboard (opt-in)

A single public ranking by lifetime XP. Design:

- Opt-in, pseudonymous, with a buddy name and a silhouette, nothing else.
- The device signs its XP total; the app submits it. No hardware, no entry.
- Rank views: all time, this month, friends (by sharing a code).
- Nothing else about the user leaves the machine. This is the one, named
  exception to local-only.

### 10.7 Sharing

A share card for level-ups and milestones: buddy, name, level, streak, one
line in the buddy's voice. Rendered locally as an image. Travel mode is the
in-person version: hand the buddy over, poke it, compare.

---

## 11. One buddy, and collecting

The buddy is the hardware. Ninety-nine percent of owners have one buddy
forever. Collecting is a cosmetic layer on that buddy, plus a rare
second-body path.

- **Skins and colors** are the collectible: earned by level, by milestones,
  by seasonal events, by limited runs.
- **Physical variants** (colorways, founders' editions) are separate
  buddies. Buying one is adopting a second creature, not reskinning the
  first.
- **A second buddy** is a deliberate act, for someone with two desks or a
  gift for a friend. Each buddy is its own creature with its own level, and
  the app shows whichever is connected.
- **No reset that keeps the name.** Retiring a buddy is a ritual with a
  memorial card in the app. This keeps the bond honest.
- **Loss and replacement.** Because identity is tied to the device, a lost
  buddy is lost. A backup and restore path to a replacement unit is wanted
  and deferred; it must feel like recovery, not cloning.

---

## 12. Identity, data, and privacy

- The creature's identity is the device. The app holds its brain state
  (traits, memory, keepsakes, level) on the Mac, and the device holds a copy
  of level, streak, and stats for travel mode.
- Nothing about agent activity leaves the machine. Not tokens, not file
  names, not transcripts, not anything the buddy has learned.
- The voice model runs on the Mac.
- The buddy sees the agent stream to learn from it (§9) and keeps only
  extracted facts. It never stores transcripts, code, file contents, or
  prompt text, in any form. There is no second copy of your work anywhere.
- Everything the buddy has learned about you is visible in the app and can
  be cleared at any time, line by line or all at once.
- Saving and restoring state across Macs is deferred (§18).

---

## 13. Business model and quality bar

- Software: free forever, no account, no subscription.
- Hardware: one-time purchase, free firmware and app updates for the life of
  the device. "Buy it once. It keeps up."
- No paid or XP-gated unlocks in v1. Cosmetics are available from the start. Limited physical editions are
  the only premium.
- Pricing is undecided until the hardware is. Whatever the number, the
  software has to make it feel like a bargain: the app, the animations, the
  sounds, and the copy are held to the standard of a premium consumer
  product, not a developer tool.

---

## 14. Hardware principles

Specifics are deferred to the hardware document. The principles are not.

- **The device is a thin terminal.** Every semantic lives in the app. The
  hardware renders state, plays sounds, and sends button and motion events.
- **Firmware updates over the air, from the app.** When agents change, the
  buddy learns the new tricks in a free update. This is the "buy it once"
  promise made real.
- **One hardware SKU per generation.** Variants are colorways, not
  capabilities.
- **Minimum inventory the experience assumes:** a color face readable at
  arm's length and legible as state across a room, a speaker, one primary
  button with press and hold and a second button strongly preferred (yes
  and no on separate keys is easier to trust), motion sensing for pokes,
  shakes, flips, and posture, a battery for a working day that can also hold
  a dim sleeping face all night, USB-C charging, and Bluetooth to the Mac.
- **It must perch and it must pocket.** Whatever the shape, it clips to a
  laptop lid and fits in a jacket pocket.
- **It reads as a designed object.** No visible board, no dev-kit cues.
- **A per-unit key** for signing XP, set at manufacture.

---

## 15. How we know it is working

The success metric is that people use Boop often and it brings them joy.
That is hard to measure and we will not fake precision. Two things stand in
for it:

- **A fun, one-tap way to tell us.** Feedback is part of the product, not a
  form. Candidates: a "how's your buddy doing" moment in the app once a week
  with three faces to tap; a "that made me smile" boop-and-hold on the
  device that logs a moment; a share card that doubles as a signal. Whatever
  ships must take under two seconds and feel like talking to the buddy, not
  filling in a survey.
- **Local usage numbers the owner can see.** Days paired this month, cheers
  acknowledged, streak. Shown to the owner as part of growth, never sent
  anywhere unless they opt into the leaderboard.

Public signals we watch without instrumenting anyone: buddies named in
posts, buddies visible in videos and desk photos, waitlist growth from
sharing.

---

## 16. Bets and risks

What this vision assumes, and what would break it.

| Bet | What breaks it |
| --- | --- |
| Newcomers to building will pay for hardware to make agent work feel companionable. | They are happy with a free app and a notification sound. |
| A small local model can be charming rather than cringeworthy. | Lines feel canned or off, and the buddy is muted within a week. |
| The completion cheer is delightful the fortieth time. | It becomes noise; the owner mutes it; the hero moment is gone. |
| Local hooks from Claude Code, Codex, and Cursor keep firing as those tools ship weekly. | A hook regression blinds the buddy for days. Mitigation: fail open, cute degraded states, fast free updates. |
| The market is too small for the agent vendors to build this themselves. | A first-party desk creature ships and owns the integration. We think this is unlikely and we design as if it is. |
| The buddy tied to the hardware is a feature, not a liability. | Lost or broken devices generate grief and support load before a restore path exists. |
| Brand and category can be settled after the product is right. | Positioning drifts and the launch story is muddled. |

---

## 17. Brand and category (undecided)

Recorded as open on purpose. The product comes first.

- **Name:** Boop, company Boop Computer, site adoptaboop.com, per the July
  decision. "Buddygotchi" stays internal.
- **Tone:** likely warmer and less wry than the engineer-facing copy in the
  older marketing doc, to match the newcomer buyer. Not decided.
- **Category:** something between a desk pet and an agent tool. Not a
  Tamagotchi, not a keyboard-shaped controller. The category name is open.
- **Visual language, palette, sound identity:** open, and owned by the
  device and app UX documents as they are written.

---

## 18. Assumptions and open questions

Assumptions made in this draft, to be confirmed or overturned:

- **A1.** Perch mode is a distinct animation set on the same connected mode,
  not a separate feature set.
- **A2.** The leaderboard is the only network feature, and it is opt-in.
- **A3.** Software-only users get a preview creature with no level and no
  rank. The level belongs to the hardware.
- **A4.** Stuck detection is heuristic (repeated similar tool calls, repeated
  errors, long silence) and tuned to be quiet. A false "stuck" is worse than
  a missed one.
- **A5.** Streak rest days are banked automatically, one per week.
- **A6.** Learning runs at one default level of detail. Whether to offer the
  user a choice of levels (events only, facts, short summaries) is open;
  see `IDEAS.md`.

Open, deferred to later documents:

- Hardware form factor, mount, weight, battery, and board (hardware doc).
- Exact level curve and XP weights (growth doc); cosmetics are independent.
- Backup and restore of a buddy to a replacement device.
- How the risk translator classifies stakes for each agent (safety doc).
- Which agents expose spend and rate-limit windows, and how (integrations
  doc). Claude Code reports rate-limit errors after the fact; a forward-looking
  window meter needs a source that does not exist in hooks today.
- Phone notifications when away. Wanted, but conflicts with local-only.
  Candidate: a relay through the user's own iCloud, no Boop server.
- Device-to-device stat comparison in travel mode (bump two buddies).
- Seasonal events and limited runs cadence.
- Which languages ship at launch. Working assumption: English and Korean.
- The exact in-product feedback mechanism (§15).
- Windows.

---

## 19. Follow-on documents

Each refines one surface of this vision. Suggested order:

1. `UX-DEVICE.md`: written. Flows first, then the six-state vocabulary,
   the cheer and its sizes, postures, sounds, buttons, travel mode.
2. `UX-APP.md`: onboarding and first wake, the menu bar creature, recap, focus
   mode, approval and risk translation, settings.
3. `UX-GROWTH.md`: level curve, XP formula and its public explanation,
   streaks, cosmetics, share cards, leaderboard.
4. `UX-VOICE.md`: personality traits, line style guide, sass ceiling, what
   the buddy learns and the "what your buddy knows" page,
   agent channel rules, model and fallback behavior.
5. `UX-HELP.md`: come-back call, stuck detection, spend awareness, nudge
   ladder, teach moments, quick commands.
6. `HARDWARE-V2.md`: form factor, mount, battery, board, cost.
