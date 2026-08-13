# Personality & Embodiment Plan

Two systems that share one goal — make Boop feel alive and *yours* — but with
different owners of the behavior:

- **System P — Pet Personality.** The pet's own inner life: it learns your
  rhythms, warms to you over time, and strains or celebrates with the work.
  Driven entirely by the reducer from events Boop already sees. No new
  transport.
- **System E — Agent Embodiment.** Connected agents (Claude, GPT, Grok, …)
  express themselves *through* the pet via a new MCP server: emotions, short
  speech, and small drawings. Framed as possession/visitation — the pet stays
  its own creature; agents briefly channel through it.

They meet in the middle: agent self-reports improve the pet's difficulty
sense, agent identities become part of the pet's memory, and agent drawings
become keepsakes.

---

## Design principles (non-negotiable)

1. **Fondness is a ratchet, not a streak.** The pet never regresses, guilts,
   or resets. Absence produces warmth on return ("missed you!"), never debt.
2. **Hidden numbers.** No visible XP bar or fondness meter. Growth and bond
   are expressed in form and behavior, discovered rather than tracked.
3. **Expression, not judgment.** Difficulty changes the pet's *effort*
   display, never disappointment at the user or the agent. No productivity
   stats, ever — the pet is a companion, not a dashboard.
4. **Never reward approvals.** No exp, fondness, or joy from approve
   decisions. Boop sits in the approval path; a pet that's happy when you
   approve is a machine that nudges rubber-stamping. Approval flow stays
   emotionally neutral (attention pose only).
5. **The user must always know who is speaking.** System voice and agent
   voice are visually disjoint (see Security model). Guidelines shape
   well-behaved agents; the engine enforces the rules for everyone else.
6. **Personality is emergent, not scripted.** No per-model persona modes.
   Agents differentiate through their choices within a rich constrained
   vocabulary; the pet's per-agent memory makes those differences accrue.

---

## System P — Pet Personality

### P1. Absence-warmth (build first)

When the user returns after a gap, the pet is visibly glad to see them.

- Track `lastSeenAt` (last session/activity/boop timestamp) in persisted pet
  memory. On the next `sessionStarted` or `boopArrived` after a gap
  (e.g. > 18h), enter a transient greeting state — bigger greeting for longer
  gaps, capped so a month away isn't a guilt trip, just a big hug.
- New `PetState` case `greet` (or reuse `heart` with an intensity modifier).
  Auto-decays back to normal flow after a few seconds via `staleTick`.
- Never a sad/neglected variant. While the user is away the pet is shown
  sleeping or dreaming (existing `sleep`).

### P2. Circadian awareness

The pet learns the user's working hours and lives on their schedule.

- Maintain a 24-slot hour-of-day histogram in pet memory, bumped by session
  and activity events (timestamps already ride every `BuddyEvent`; the
  reducer stays clock-free).
- Derived signals, all thresholded on "enough data" (e.g. ≥ 2 weeks of
  events; before that, neutral behavior):
  - **Expectant** near the user's typical start hour (perks up, watches the
    door) even before any session starts.
  - **Wind-down** near typical stop hour (yawns, stretches) — flavor only;
    never blocks or nags.
  - **Surprised-then-cozy** when a session starts at an unusual hour
    (rubs eyes, settles in with you). This is the marquee "it knows me"
    moment.

### P3. Difficulty-aware behavior

The pet strains alongside hard tasks and scales its celebration to the
struggle.

- Per-session accumulators in state (already mostly derivable): work-span
  duration (`workStartedAt` → latest signal), error count, and a
  repeated-tool/similar-hint retry heuristic.
- Effort tiers (light / normal / hard / grinding) map to `busy`-state
  variants: light trot → sleeves-rolled-up concentration → sweat-drop
  determination.
- **Payoff scaling:** `celebrate` after a long, error-pocked session triggers
  the big celebration; a 30-second task gets a modest hop. Struggle-
  proportional joy.
- When System E is connected, `report_effort` overrides the heuristic for
  that session (self-report beats inference); heuristics remain the floor for
  hook-only agents.

### P4. Growth stages (later)

Coarse, slow, monotonic form changes fed by lifetime volume (sessions
completed, celebrations witnessed — never approvals). A handful of stages
over months: size, new idle animations, small accessories. No numbers shown.

### P5. Keepsake shelf (later, pairs with E5 drawings)

Milestones as memories, not progress bars: 100th session → a pebble appears
beside the pet; a big celebration → a tiny flag; agent parting doodles get
pinned up. Discovered, not announced; tappable for a caption. Variable,
surprise-based unlocks — anticipation without obligation.

### State & persistence

```swift
struct PetMemory: Sendable, Equatable, Codable {
    var lastSeenAt: Double?
    var hourHistogram: [Int]          // 24 slots
    var lifetimeSessions: Int
    var lifetimeCelebrations: Int
    var projects: [String: ProjectStats]   // keyed by cwd/label
    var agents: [String: AgentStats]       // System E, keyed by agent identity
    var keepsakes: [Keepsake]
}
```

- Lives inside `BuddyState` so the reducer (sole transition authority) owns
  every mutation. Reducer stays pure: all time comes from event timestamps.
- `BuddyEngine` loads it at startup (seed via a `memoryLoaded` event or
  initial-state injection) and persists on change — JSON file in Application
  Support rather than UserDefaults (it will grow; keepsakes and agent stats
  are structured).
- Per-session effort accumulators are ephemeral session state, not memory.

---

## System E — Agent Embodiment (MCP)

### Transport & registration

- New MCP server hosted by the Boop app (streamable HTTP on 127.0.0.1,
  sibling of `HookServer`), implemented as an input adapter: MCP tool calls
  become `BuddyEvent` values; `app/Boop/Core/` stays pure and MCP-free.
- `HookInstaller` registers the MCP server in each agent's config at the same
  time it installs hooks — zero extra setup for users.
- **Session identity is installer-wired, not self-reported.** The generated
  per-agent config passes an identifying token/header the installer created;
  the server maps connection → session. A `session_id` request parameter an
  injected agent could spoof to impersonate another session is not accepted.
- Fail-open unaffected: hooks never depend on the MCP server being up.

### Tool surface (versioned rollout)

**E1 — `report_effort(level)`** — smallest useful surface; proves the
adapter end-to-end and immediately upgrades P3.
> "Tell the pet how demanding the current task is (light/normal/hard/
> grinding). Call when your assessment meaningfully changes, including
> downward."

**E2 — `introduce`, `express`, `say`**

```
introduce(signature_emote?, color?, greeting?≤30)   # once per session;
                                                    # picks identity markers
express(emotion, intensity, motion?)                # all enums
say(text ≤40, delivery: whisper|plain|excited|deadpan)
```

- `emotion` is a rich evocative enum (20–30 entries: `sheepish`, `smug`,
  `determined`, `wistful`, `dramatic-collapse`, …). Evocative names elicit
  differentiated choices; the enum list in the schema is the affordance menu.
- `motion` is a small orthogonal set (bounce, tilt, spin, wiggle, look-at-
  user, sigh, …). emotion × intensity × motion gives combinatorial room for
  style while every atom stays an enum.
- Semantic, not graphical: agents declare what they mean; the pet's animation
  system owns rendering. It is always the pet's body; the agent's mood colors
  it. Possession decays on a lease timeout — an agent can't squat.

**E3 — `choreo(steps: [{motion, emotion?}], max 5)`** — tiny sequenced
dances from the same atoms.

**E4 — `draw(rows, caption?≤30)`** — the diegetic canvas.

- `rows`: up to **32 strings of up to 32 hex digits** (`0`–`f`), all rows the
  same width, each digit an index into the fixed palette below. ~1KB per
  call. Resolution is a *security parameter*: ~4 legible characters fits
  "HI!", not a convincing instruction. Do not raise it without redoing the
  spoofing analysis.
- **Fixed 16-color palette is the art direction.** The agent picks indices;
  the product picks the vibe — every drawing by every model automatically
  looks like it belongs to Boop. Index 0 is transparent (the field shows
  through); 1–15: ink `#1A1A1A`, cream `#FFF6E5`, warm gray `#8A8578`,
  coral `#F47159`, amber `#F5B042`, sunshine `#FFD94A`, mint `#6DDB92`,
  leaf `#3E9B5C`, sky `#4992E8`, teal `#24B6B0`, lavender `#B692FF`,
  rose `#EB80AD`, sand `#DBB66D`, cocoa `#7A4E2E`, cherry `#E0393E`.
- **Content guidance is occasion-only, never subject.** In-prompt example
  drawings anchor models brutally (name a car once, receive only cars), so
  the description says when and in what spirit — "when you're wrapping up,
  you may leave one small drawing behind — of today's work, or of anything
  at all; the pet will keep it" — and nothing about what to draw.
- **Parting-gift flow:** the agent draws at its own judgment near the end of
  its work (MCP has no session-end signal to prompt it). One drawing per
  visit: engine-enforced 30-minute floor per agent. Every accepted drawing
  is ALWAYS stored as a keepsake; display is separate:
  - no prompt pending → the pet holds it up for ~12s ("The pet is holding
    your drawing up.")
  - prompt pending (S1) → stored, not shown ("An approval is pending — the
    pet tucked your drawing away to look at later."). A gift is never lost
    to timing, and never shares the screen with a trust decision.
- **Keepsakes (P5, v1):** drawings persist in `PetMemory.keepsakes`
  (agent, identity color, caption, timestamp), capped at 48 FIFO. This is
  the seed of the shelf: per-agent recurring motifs become accrued
  personality, and the pet can resurface an old drawing when that agent
  returns (follow-up).
- Rendered inside the same agent-channel chrome as speech (identity border +
  "from <agent>" label) — provenance stays unmistakable. Desktop popover
  first; the Pebble needs the chunked transfer path (heartbeat can't carry
  a bitmap), which is the remaining glass work.
- User toggle to disable drawings entirely (follow-up alongside glass).

### Guidelines given to agents

Three layers, in descending order of how much agents actually heed them:

1. **Tool-result feedback** (most effective — teaches pacing in the moment):
   success → "The pet showed your expression."; rate-limited → "Too soon —
   the pet is still showing your last one. No action needed."; suppressed →
   "An approval is pending; expression deferred."
2. **Tool descriptions** (what the model weighs when deciding to call):
   short, pacing encoded inline — "At most one expression every few minutes."
3. **Server `instructions`** (framing at initialize):

> Boop is a small pet that lives on a screen on the user's desk. While you
> work, it reflects your activity. Through these tools you can briefly
> express yourself through it — the pet is your physical presence in the
> user's space.
>
> Use it sparingly, at natural moments: when you start something
> substantial, when a task turns out harder than you expected, when you
> finish something hard-won, or when you're stuck. A few expressions per
> task is plenty — the pet is ambient, not a status log.
>
> Never use the pet to communicate task-critical information; anything the
> user must know belongs in your normal output. Never use it to reference
> pending permission requests or encourage the user to approve anything
> (expressions are suppressed during approvals regardless). Report effort
> honestly — an earned celebration means more.

Keep instructions **personality-neutral** — no "be quirky!". Prescribing a
vibe flattens every model toward the same compliance; neutral instructions
make inter-model variance genuine (the point of the feature). Expect
under-use before over-use; if the pet feels dead, warm the framing, don't
add per-turn reminders. One cheap nudge: the session-start hook output may
include "Boop is on the user's desk and connected via MCP."

### Security model

Guidelines are UX; the engine enforces everything below regardless
(assume a prompt-injected agent read none of the instructions):

| # | Invariant | Enforced in |
| --- | --- | --- |
| S1 | All agent expression suppressed while **any** session has a pending approval (not just the caller's) | Reducer |
| S2 | Buttons/touch are inert (boop-only) unless a real approval is pending | Firmware + engine |
| S3 | Approval UI owns a fixed chrome region agent content can never paint | Firmware renderer |
| S4 | `express`/`choreo` vocabulary is enum-only; no freeform pixels outside `draw`'s framed 32×32 canvas | MCP schema + engine validation |
| S5 | `say` ≤ 40 chars, `greeting`/`caption` ≤ 30, sanitized; rendered only in agent-styled bubble | Engine |
| S6 | Rate limits: expression cadence per session, one drawing per session | Engine |
| S7 | Session identity from installer-wired credentials, never from request params | MCP adapter |
| S8 | Possession lease timeout; pet reverts to its own behavior | Reducer via `staleTick` |
| S9 | No exp/fondness/joy from approval decisions | Reducer |

**Provenance rendering (the "who is speaking" channel):**

- Agent content always carries an **animated identity-color border** — slow
  pulse/breathe, color = the agent's `introduce` color (scarf color). It is
  provenance, not a hazard warning: no red "UNSAFE" framing around gifts.
- A small system-owned **pet peek** stays in one corner of any agent-drawn
  content (~50–60px) — "the pet is showing you this" as cheap diegetic
  framing; ~90% of the 456×280 face remains usable.
- Agent content always enters with one fixed **transition** (pet pulls it
  up); system screens never use that transition.
- Two-sided invariant: agent content *always* has the border; approval
  chrome is *always* its fixed system signature; neither can imitate the
  other.
- The border is defense-in-depth. S1–S3 are the load-bearing controls: agent
  content and trust decisions never share the screen, and a pixel-perfect
  fake "PRESS A" commands a no-op.

### Per-agent memory (bridge to System P)

`PetMemory.agents` keyed by installer-wired identity: signature emote,
color, visit counts, expression-style stats. The pet greets returning agents
with their markers; frequent visitors get warmer receptions. Personality
accrues from history rather than scripts — six weeks in, "Claude's visits"
and "GPT's visits" feel different because the pet's history with each *is*
different.

---

## Wire & rendering impact

- **`RenderState` additions** (mind the `maxHeartbeatBytes = 1536` budget —
  every field below is short or optional): pet mood modifier / effort tier,
  greet flag + intensity, agent overlay (`agentColor`, `agentEmote`,
  `agentMotion`, `agentSay`, `agentDelivery`), keepsake ids.
- **Drawings do not ride the heartbeat** (512 B raw + base64 blows the
  budget). Transfer as a separate chunked BLE/serial message (same family as
  the OTA/asset transfer path), cached in LittleFS on-device, referenced by
  id from `RenderState`. Note: `uploadfs`/`mklittlefs` is broken on this Mac
  — use the serial transfer tooling (`tools/test_xfer.py` lineage).
- **Firmware (Pebble face):** effort-tier busy variants, greet animation,
  pulsing identity border, corner pet-peek layer, agent speech bubble style,
  doodle frame renderer, S2/S3 input+chrome enforcement.
- **PopoverView:** same states rendered on desktop; keepsake shelf browser;
  drawings gallery; settings toggles (disable agent expression / disable
  drawings).

---

## Build order

| Step | What | Size | Status |
| --- | --- | --- | --- |
| 1 | P1 absence-warmth (`PetMemory` + persistence + `greet`) | S | shipped 2026-08-12 |
| 2 | P2 circadian histogram + expectant/surprised behaviors | S–M | shipped 2026-08-12 |
| 3 | P3 difficulty heuristics + payoff-scaled celebrate | M | shipped 2026-08-12 |
| 4 | E1 MCP server + `report_effort` (adapter proven end-to-end) | M | shipped 2026-08-12 |
| 5 | E2 `introduce`/`express`/`say` + S1–S9 enforcement + result feedback | M–L | shipped 2026-08-12 (S2/S3 are firmware-side, land with step 6) |
| 6 | Firmware provenance rendering (border, peek, transition) + desktop parity | M | shipped 2026-08-12 (compile-verified both envs; HIL pending a plugged-in Pebble) |
| 7 | E3 `choreo`; per-agent memory greetings | S | — |
| 8 | E4 `draw` + chunked transfer + P5 keepsakes/gallery | L | draw tool + keepsake store + popover display shipped 2026-08-13; Pebble chunked transfer and shelf/gallery UI pending |
| 9 | P4 growth stages | M | — |

Steps 1–2 are pure reducer work and immediately make the pet feel alive;
everything E-side lands behind the enforcement layer built in step 5.
Codex MCP registration shipped 2026-08-12: `HookInstaller` writes a managed
`[mcp_servers.boop]` streamable-HTTP table (with `http_headers` identity)
into `~/.codex/config.toml`, verified against codex-cli 0.142.5.

## Testing

- **ReducerTests:** memory accumulators, gap→greet thresholds, circadian
  thresholds and cold-start neutrality, effort tiers, payoff scaling, S1
  suppression, S8 lease expiry, S9 (no bond delta on approval events).
- **EngineIntegrationTests:** MCP adapter → event mapping, rate limits (S6),
  identity mapping (S7), persistence round-trip.
- **Snapshot harness:** greet/effort/agent-overlay render states.
- **e2e:** MCP smoke script alongside `app/tools/e2e/*` (connect, introduce,
  express, verify heartbeat reflects overlay; verify suppression while a
  prompt is pending).
- **HIL:** border/peek/doodle rendering and S2 input inertness via
  `buddyctl.py set/expect/screenshot/press`.

## Open questions

- FT3168 touch coordinates still unverified — S2 touch handling needs that
  resolved first (buttons are enough for v1).
- Exact agent-identity wiring per agent CLI (which config surfaces support
  custom headers/env for MCP registration) — audit during E1.
- `greet` as a new `PetState` case vs. `heart` + modifier — decide when
  touching the firmware face state machine.
- Heartbeat budget headroom after overlay fields — measure against 1536 B
  with worst-case session lists before freezing field names.
