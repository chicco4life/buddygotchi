# Architecture

Status: v1 target architecture, first draft, 2026-09-08. Implements
`VISION.md`, `UX-DEVICE.md`, and `IDEAS.md` idea 1. The current codebase is
described in `research/eng/ARCHITECTURE-APP.md`; this document says what the
v1 system should be, and §11 says what is kept from today and what is new.

---

## 0. The whole system in one picture

```
 Claude Code      Codex        Cursor
     │               │            │          local hooks; fail open
     ▼               ▼            ▼
 ┌────────────────────────────────────┐
 │  hook script / BoopSignal          │  one bash script + one tiny binary
 │  caps bytes, POSTs to localhost    │
 └────────────────┬───────────────────┘
                  ▼  HTTP, token-authed, 127.0.0.1
 ┌──────────────────────────────────────────────────────────────────┐
 │  Mac app (the brain)                                             │
 │                                                                  │
 │  HookServer ──► Extractor ──► Engine ──► Reducer ──► BuddyState  │
 │   routes        raw→facts     orchestration  pure     projection │
 │   MCP server    discards raw  clock, timers  no I/O              │
 │                                   │                              │
 │        ┌──────────────────────────┼───────────────────────┐      │
 │        ▼                          ▼                       ▼      │
 │     Memory                     Growth                   Voice    │
 │     working / episodic /       XP, level, streak,       local LLM│
 │     profile; nightly           cosmetics, signed        + authored│
 │     reflection                 ledger                   fallback │
 │        │                          │                       │      │
 │        └──────────────► Occasion detector ◄───────────────┘      │
 │                                   │                              │
 │                                   ▼                              │
 │                          OutputProviders                         │
 │                    Desktop            Device                     │
 │                    menu bar creature  RenderState v2 → BLE       │
 └──────────────────────────────────────────┬───────────────────────┘
                                            │  Nordic UART, newline JSON
                                            ▼
 ┌────────────────────────────────────────────────────────────────┐
 │  Buddy firmware (thin terminal)                                │
 │  parse line → validate → device model → renderer (6 states)    │
 │  buttons, motion, posture, sound, travel-mode stats, NVS, OTA  │
 │  sends: decision, boop, collect, posture, battery, motion      │
 └────────────────────────────────────────────────────────────────┘
```

Two rules shape everything: **the Mac app is the brain and the device is a
thin terminal**, and **the reducer is pure**. Everything that touches the
outside world sits either before the reducer (adapters and the extractor) or
after it (outputs). Memory, growth, and voice are services the engine calls
around the reducer, never from inside it.

---

## 1. Principles

1. **Pure core.** The reducer takes state and an event and returns state. No
   I/O, no clock, no defaults, no model calls, no BLE. Time arrives as
   timestamps on events and as ticks from the engine.
2. **Thin device.** Firmware renders a state the app sends and reports
   inputs. It never composes text, never scores anything, never decides. The
   one exception is travel mode, where it displays a snapshot it was given.
3. **Fail open.** If the app is down, hooks exit successfully and the agent
   continues natively. If the device is gone, the app carries on. If the
   model is slow, authored lines carry on.
4. **See, extract, forget.** Raw hook payloads live in memory only as long
   as the extractor needs them. Nothing raw is stored, logged, or sent to
   the model.
5. **One wire contract.** The device speaks one versioned render state and a
   small command set. Every display derives from `BuddyState`; the device is
   just the display that happens to be over Bluetooth.
6. **Local only, one exception.** The leaderboard client is the only code
   that opens a socket to anything but localhost and the device.
7. **Utility before expression.** Approval and needs-you paths never wait on
   memory, growth, or voice. Those enrich; they cannot block.

---

## 2. Agents and hooks

**What is installed.** One bash script registered in each agent's hook
config, plus a small helper binary for Cursor. Same as today. The installer
writes the config, verifies it, and can repair it.

**Events subscribed,** per agent, mapped to one internal vocabulary:

| Internal | Claude Code | Codex | Cursor |
| --- | --- | --- | --- |
| session start / end | SessionStart, SessionEnd | SessionStart, SessionEnd | sessionStart, sessionEnd |
| turn start | UserPromptSubmit | UserPromptSubmit | beforeSubmitPrompt |
| tool call | PreToolUse | PreToolUse | preToolUse, beforeShellExecution, beforeMCPExecution |
| tool result | PostToolUse, PostToolUseFailure | PostToolUse | afterShellExecution, postToolUse, postToolUseFailure, afterFileEdit |
| needs you | PermissionRequest, Notification (elicitation, idle) | PermissionRequest | beforeShellExecution and beforeMCPExecution with a decision, stop with needs-input |
| turn end | Stop, StopFailure | Stop | stop, afterAgentResponse |

**What the script forwards.** Today: event name, session id, cwd, tool name,
and a truncated hint. v1 adds, for tool call and tool result events: the
full command or tool input, exit status or error class, and the first and
last 512 bytes of output. For turn end: the agent's closing message capped
at 2 KB. Everything else in the payload is dropped at the script. Total
request body capped at 8 KB.

**Fail open** is enforced at the script: short connect timeout, any failure
exits zero, and the approval path returns "passthrough" so the agent shows
its own prompt if Boop cannot answer.

---

## 3. HookServer

Localhost HTTP on a fixed port with a per-install token. Same shape as
today.

| Route | Purpose |
| --- | --- |
| `POST /hook/event` | Everything that is not blocking. Returns immediately. |
| `POST /hook/approve` | Needs-you. Holds the connection until a decision or timeout, then returns allow, deny, or passthrough. |
| `POST /hook/signal` | Cursor's helper path. |
| `GET /healthz` | Liveness for the script and the tests. |
| `/mcp` | The agent channel (§7). |

The server does three things and nothing else: authenticate, parse the
per-agent payload into a `RawHookPayload`, and hand it to the extractor. It
does not touch state. The Cursor auto-approve rule for read-only shell
commands stays here because it is a parsing concern and must read the full
command.

---

## 4. Extractor

New in v1. Turns a `RawHookPayload` into one or more `BuddyEvent`s and
`Fact`s, then drops the payload.

```
RawHookPayload
   │
   ├─ session/turn/tool lifecycle ──► BuddyEvent (sessionStarted, turnStarted,
   │                                   toolCalled, toolResulted, turnEnded, …)
   ├─ needs-you ────────────────────► BuddyEvent.needsYou + Gloss + Stakes
   ├─ tool call + result ───────────► Fact (runner, goal signature, outcome)
   └─ turn end ─────────────────────► Fact (turn summary source, error class)
```

Sub-components:

- **Per-agent parsers.** One per agent, thin. They know payload shapes and
  nothing else.
- **Runner table.** Recognizes test, build, lint, typecheck, and script
  commands across the common ecosystems, and normalizes each to a goal
  signature (command with paths, timestamps, and volatile flags stripped,
  plus project id). Extensible by a data file, not code.
- **Outcome reader.** Exit status where present; otherwise runner-specific
  patterns on the capped output. Returns pass, fail, or unknown. Unknown is
  a first-class answer; guessing is not allowed.
- **Stakes classifier.** Tool plus command to fine / check it / careful.
  Destructive shell, deletes outside the project, network, credentials, and
  package installs are careful. Deterministic rules, tested by fixture.
  Control characters in a command force careful.
- **Gloss writer.** One plain-English line per tool call for the needs-you
  card, from templates keyed on tool and command class. Never a model on
  this path; it has to be instant and never wrong.
- **Tone and topic.** Prompt text reduced to a tone class and up to three
  topic tags. The text is then discarded. Used for personality drift and
  for the profile's likes and dislikes.
- **Project id.** Derived from cwd and, when available, the git remote.

The extractor is pure except for the runner table load and is tested with a
fixture corpus of real payloads per agent. When a field is missing because
an agent changed, it degrades to lifecycle events only and emits one
`adapterDegraded` event so the buddy can say so once.

---

## 5. Core: engine, reducer, state

**BuddyEngine** is the orchestrator. It owns the clock, receives events from
the extractor, the device, and the UI, feeds them through the reducer,
calls the services, and fans the resulting state out to outputs. Approval
continuations (the held HTTP connections waiting for a decision) live here.

**Reducer** is a pure function over `InternalState`. It owns:

- **Sessions.** One per agent session with source, project, current state,
  current tool, effort accumulators, and pending prompt.
- **The six states** and their parameters, derived from sessions: asleep,
  idle, working (effort), needs you (prompt, count), done (cheer size), uh-oh
  (kind: error, stuck, hungry). Overlays greet and boop. One creature: the
  reducer collapses all sessions into one state by priority: needs you >
  uh-oh > done > working > idle > asleep.
- **Working memory.** Goal signatures with attempt counters and start
  times, per session. This is what makes the tenth try countable.
- **Effort.** Elapsed time, retries, errors, and agent self-report into
  light / hard / grinding.
- **Cheer sizing.** On turn end: hop by default; cheer when effort was hard
  or the turn had errors; dance when a goal passed after many attempts or a
  long red streak ended. Thresholds in one place, tunable.
- **Nudge ladder timing.** Rungs advance on ticks. Dismissals halve, three
  auto-snooze. Focus mode gates rung 1 and 2.
- **Stuck detection.** Repeated goal signatures without a pass, repeated
  identical errors, or silence past a threshold mid-turn, all tuned quiet.
- **Occasion detection.** Rules that turn state transitions and facts into
  `Occasion`s: hard-won pass, red streak ended, back after absence, same
  file again, late night, nth rate limit, ritual observed. Occasions are
  data; the voice decides what to say.

**BuddyState** is the public projection: the one creature's state and
parameters, the session dots, the pending card, the current bubble, the
gift, greet level, focus flag, and the growth snapshot. Both outputs render
only from this.

---

## 6. Memory, growth, and reflection

Services beside the reducer. The engine calls them with facts and occasions
and feeds their results back as events (`memoryLoaded`, `profileUpdated`,
`levelChanged`), so the reducer stays pure and the state stays the single
source of truth.

**Episodic store.** SQLite on the Mac. Structured facts only: turn
boundaries, goal outcomes, effort, errors, projects, tone and topic tags,
occasions. Thirty-day retention. No text longer than a line, no raw.

**Profile.** A short list of human-readable lines with a source and a
confidence: "tests first, usually," "works Sunday mornings," "dislikes
regex." Stored as its own table, rendered as the "what your buddy knows"
page, deletable line by line. Clearing it emits `profileCleared`; the buddy
keeps name, level, and bond.

**Personality.** Four slow traits on 0 to 255 with single-digit deltas per
day, plus a hidden bond that only rises. Drift inputs: hours, tool mix,
outcomes, nudge responses, check-ins, tone. Never approvals.

**Growth ledger.** Append-only XP entries with source and timestamp, the
public formula applied at read time so the formula can change without
rewriting history. Level, streak with banked rest days, and the cosmetics
inventory derive from the ledger. Each day's total is signed by the device
key when a device is paired (§9.3).

**Reflection.** A scheduled job that runs when the Mac is idle and on
power. Reads the day's facts and the capped closing messages, asks the
voice model for three to five candidate profile lines and trait deltas,
applies caps, writes them. Runs in minutes, not seconds, and may use a
larger model than the live voice.

---

## 7. Voice and the agent channel

**Voice service.** Input: an occasion or state transition, up to three
profile lines, the personality vector, the agent name, time of day, and the
owner's language. Output: one line under the device's byte budget, and a
longer app variant when asked. Constraints:

- Runs a small local model through a runtime abstraction (MLX or llama.cpp
  on Apple Silicon; the choice is behind an interface).
- Budget under one second for a device line. Past the budget the authored
  fallback line is used and the model result is discarded, so the device
  never waits.
- Authored fallback banks per language and per occasion, used on machines
  that cannot run the model at all.
- Sees only structured inputs. Never a payload, never a transcript, never
  code.
- Sass ceiling and target enforced by prompt and by a post-filter that
  rejects lines addressed at the owner in the second person with negative
  tone.

**Agent channel.** The MCP server at `/mcp`. Tools: `introduce`,
`express`, `say`, `draw`, `report_effort`, and one new `tell` for "what I
am trying to do and how it went." Enforced by the engine, not by
guidelines: suppressed while a prompt is pending, enum-only emotions,
byte-capped text, per-agent rate limits, rendered in a visibly different
frame, never affects XP or traits.

---

## 8. Outputs

`OutputProvider` stays: `start`, `stop`, `stateDidChange(prev, next)`.

**Desktop.** The menu bar creature and popover render `BuddyState` directly
with the same six states and the same cheer sizes as the device. Also owns
notifications (rare, opt-in), sounds when no device is paired, the needs-you
card in the app, the recap screen, the profile page, settings, onboarding.

**Device.** Two parts: the mapper from `BuddyState` to `RenderState v2`, and
the BLE transport. The mapper applies byte budgets and truncates on
character boundaries. The transport sends a frame on every state change and
a keepalive every few seconds, receives commands, and runs the acked
transfer protocol for firmware updates and cosmetics.

---

## 9. The wire contract

### 9.1 Host to device: RenderState v2

One JSON object per line. Absent keys mean "unchanged or none." Byte
budgets per field match the firmware's fixed buffers. Frame cap 1536 bytes.

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | int | Contract version |
| `state` | enum | asleep, idle, working, needsYou, done, uhoh |
| `effort` | enum | light, hard, grinding |
| `cheer` | enum | hop, cheer, dance |
| `uhoh` | enum | error, stuck, hungry |
| `overlay` | enum | greet, boop |
| `greetLevel` | int | 0 to 3 |
| `dots` | int | Active sessions, 0 to 5 |
| `dotAlert` | int | Index of a red-tinted dot, or absent |
| `card` | object | `{id, tool, gloss, stakes, n, of}` for needs you; `{kind, text}` for pairing and update |
| `bubble` | string | One line, byte-capped, shown for four seconds |
| `gift` | bool | Orb pending |
| `giftLine` | string | The story line shown on collect |
| `focus` | bool | |
| `mute` | int | Volume step or mute |
| `posture` | enum | Optional override: desk, perch, travel |
| `cosmetic` | object | `{skin, accessory, silhouette}` ids |
| `snap` | object | Travel snapshot: `{name, level, xp, xpNext, streak, best, rest, days, tasks, today, biggest}` |
| `agent` | object | Channel overlay: `{name, color, emotion, say}` never with a card |
| `t` | int | Host time for the device clock |

### 9.2 Device to host

| Message | When |
| --- | --- |
| `{"cmd":"decision","id":…,"d":"allow"\|"deny"}` | A button answered an armed card |
| `{"cmd":"collect"}` | Orb popped |
| `{"cmd":"boop","hold":bool}` | Tap or pet, rate-limited |
| `{"cmd":"posture","p":…}` | Posture changed |
| `{"cmd":"motion","m":"shake"\|"flip"\|"pickup"}` | Display-only, mirrored to the desktop |
| `{"cmd":"battery","pct":…,"charging":bool}` | On change and on connect |
| `{"cmd":"focus","on":bool}` | Secondary hold toggled it |
| `{"cmd":"status"}` reply | Board id, firmware, key id, stats snapshot |
| `{"ack":…}` | Transfer and update replies, as today |

### 9.3 Device key and signed growth

Each device holds a per-unit key in protected storage, provisioned at
manufacture. The app sends the day's XP total; the device returns a
signature over `{unitId, day, xp}`. The app stores it in the ledger. The
leaderboard client submits `{buddyName, silhouette, xpTotal, signatures}`
and nothing else. No device, no signature, no rank.

### 9.4 Transport

Nordic UART over BLE, newline-delimited JSON both ways, 180-byte write
chunks, as today. Bonded with LE Secure Connections. Frames on change plus a
keepalive; the device treats a minute without frames as link lost. Time
sync rides on the frame. Firmware updates and cosmetic assets use the
existing chunk-and-ack protocol with back-pressure.

---

## 10. Firmware

```
 BLE / USB line ──► parse ──► validate (version, enums, byte caps)
                                 │
                                 ▼
                          device model          ◄── buttons, IMU, battery
                    (last RenderState + local:    (debounced, arm delay,
                     posture, brightness, orb,     wake-press guard)
                     card armed, travel snap)
                                 │
                                 ▼
                          renderer, by screen priority
                    system card > needs-you card > decision feedback >
                    uh-oh bubble > stats > bubble > overlay > face+field+dots+orb
                                 │
                                 ▼
                    face parts (eyes, brows, mouth, cheeks, body, feet)
                    field, sparks, sound engine (7 motifs, manners)
```

Responsibilities:

- **Message handling.** One line, one parse, one validation pass. Unknown
  keys are ignored so old firmware survives new fields. Bad enums fall back
  to the last good value. A frame never blocks rendering; it updates the
  model and the next tick renders it.
- **Local autonomy.** The device owns what must work without the app: the
  arm delay and wake-press guard on the card, the shutdown hold ladder,
  posture detection from the IMU, dim ladder, boop and pet reactions,
  shake and flip, travel-mode stats cards from the last snapshot, and the
  sleep animation.
- **Persistence.** NVS holds the unit key, bond, the last travel snapshot,
  cosmetic ids, volume, and a first-wake-done flag. Nothing else. The Mac is
  the source of truth for everything the snapshot summarizes.
- **Sound.** Seven motifs in a table, a non-blocking scheduler, and the
  manners (one-second spacing, ten-second cheer spacing, café floor).
- **Rendering.** Per-frame incremental, spring physics for squish and
  dangle, no blocking sequences. Parts compose; there is no sprite per
  state.
- **Updates.** OTA over the existing acked protocol, with a board id in the
  status reply so the app never sends the wrong image.
- **Debug.** USB serial mirrors the BLE line protocol so hardware-in-the-loop
  tests can drive the device without a radio, as today.

What is removed from today's firmware: the species and character menu, the
glance card, the orb-per-session fireflies, the mood engine, and any text
composition. Six states, one card, one bubble.

---

## 11. Kept, changed, new

| Area | Today | v1 |
| --- | --- | --- |
| Hook script and installer | Keep | Forward more fields with byte caps |
| HookServer routes and auth | Keep | Add `RawHookPayload` handoff to the extractor |
| Cursor auto-approve rule | Keep | Unchanged |
| Extractor | Does not exist; hints extracted inline | New |
| Engine and pure reducer | Keep | New state vocabulary, working memory, cheer sizing, occasions |
| PetMemory | Keep the shape | Grows into episodic store plus profile; moves persistence out of the reducer's file into a store service |
| Growth | Does not exist | New ledger, level, streak, cosmetics, signing |
| Voice | Does not exist | New service with runtime abstraction and fallback banks |
| MCP agent channel | Keep | Add `tell`, keep sandbox rules |
| Desktop output | Keep | Re-render for six states; add profile page, recap, onboarding |
| RenderState | Keep the mechanism | v2 fields; contract version field |
| BLE transport, OTA, acks | Keep | Add device-to-host commands; board id |
| Firmware | Keep HAL, BLE, OTA, HIL | Rewrite the model and renderer around six states |
| Leaderboard client | Does not exist | New, opt-in, the only network code |

---

## 12. Key flows end to end

**Needs you, with budget.**

1. Agent fires the permission hook. Script POSTs `/hook/approve` and holds.
2. Server parses, extractor produces `needsYou` with gloss and stakes.
3. Reducer enters needs-you; engine registers the continuation.
4. Device output maps to a frame with the card; BLE sends it. Target under
   500 ms from hook to screen.
5. Firmware arms the card after its delay, plays "meep?", renders.
6. Primary tap. Firmware sends `decision`. Target under 300 ms from press
   to the app.
7. Engine resolves the continuation; the held HTTP call returns allow; the
   agent proceeds. The next frame clears the card. Firmware shows "yes!"
   only when that frame arrives.
8. Timeout or app gone: script returns passthrough; the agent's own prompt
   appears.

**The tenth try.**

1. Ten `toolCalled` and `toolResulted` pairs with the same goal signature;
   the extractor reads nine fails and one pass.
2. Working memory counts attempts; effort reaches grinding; the device
   shows sweat.
3. Turn ends. Cheer sizing picks dance. Occasion detector emits hard-won
   pass with attempts and elapsed time.
4. Voice gets the occasion, the project line from the profile, and the
   personality. Returns "ten tries. nice job on the tests." in under a
   second, or the authored fallback.
5. Frame carries `cheer: dance`, `gift: true`, `giftLine`. Device dances,
   orb settles. Collect shows the line.
6. The fact and the occasion go to the episodic store. XP entry for a
   completed task with effort. Nothing raw was kept.

**Unlink to travel and back.**

1. Every frame carries `snap`; the device persists the latest to NVS.
2. Link lost on battery: a minute of glancing at the Bluetooth mark, then
   yawn, then travel idle. Stats cards render from NVS.
3. Link returns: device sends `status` and `battery`; app sends a frame
   with `overlay: greet` and the level from the gap. Day's XP gets signed.

**Nightly reflection.**

1. Scheduler sees idle and power. Reads the day's facts and closing
   messages from the store.
2. Voice model proposes profile lines and trait deltas. Caps applied.
3. `profileUpdated` and `traitsChanged` events go through the reducer.
   Closing messages are deleted; facts age out at thirty days.

**First wake and pairing.**

1. First power: firmware's first-wake flag is unset. Plays the first-wake
   ritual and shows the Bluetooth mark.
2. App discovers, bonds, sends a frame. Mark turns solid; hop.
3. First real agent event: frame carries `cosmetic` with the first color;
   firmware shimmers. First `turnEnded` gets `cheer: cheer` regardless.

---

## 13. Latency budgets

| Path | Budget |
| --- | --- |
| Hook to card on device | 500 ms |
| Button to decision at the app | 300 ms |
| State change to frame on device | 250 ms |
| Authored line | instant |
| Model line for the device | 1 s, then fallback |
| App-side longer line | 3 s |
| Reflection | minutes, off the interaction path |

---

## 14. Storage map

| Lives on | What | Retention |
| --- | --- | --- |
| Mac, SQLite | Facts, occasions, XP ledger with signatures, profile lines, personality, cosmetics inventory | Facts 30 days; the rest for the life of the buddy |
| Mac, memory only | Raw hook payloads, closing messages until reflection runs | Seconds to one night |
| Mac, files | Authored line banks, runner table, stakes rules, model weights | Shipped with the app |
| Device, NVS | Unit key, bond, travel snapshot, cosmetic ids, volume, first-wake flag | Until replaced |
| Leaderboard server | Buddy name, silhouette, XP total, signatures | Opt-in |

No transcript, code, file content, or prompt text is stored anywhere, in
any form.

---

## 15. Testing

- **Reducer.** Pure, exhaustive unit tests: state collapse across sessions,
  cheer sizing thresholds, nudge ladder timing, working memory, occasions.
- **Extractor.** Fixture corpus of real payloads per agent and per version,
  with expected events, facts, stakes, and glosses. Runs in CI. This is the
  guard against agent releases changing payloads.
- **Voice.** Golden tests on the authored banks; property tests on the
  post-filter; latency test that the fallback fires past budget.
- **Wire.** Encoder tests for every byte budget on character boundaries;
  version compatibility tests against the previous firmware.
- **Firmware.** Hardware-in-the-loop over USB: drive frames, press buttons,
  assert screenshots and outbound commands, as today.
- **End to end.** Scripted sessions per agent against a running app; the
  ten-scenario bench from the sprint plan, extended with the tenth-try case.

---

## 16. Open questions

- Should the extractor run in-process or as a separate helper so a parsing
  crash cannot take the engine down? Leaning in-process with a hard
  try-catch boundary and the fixture corpus as the real defense.
- Where the runner table lives: shipped file with updates through the app,
  or fetched. Shipped; the app updates often enough.
- Whether the device signs daily or per session. Daily is enough for the
  leaderboard and cheaper on the radio.
- Model runtime: MLX versus llama.cpp, decided by the latency bench across
  the Macs the audience actually owns.
- Windows changes the hook script, the server host, and the model runtime,
  and nothing in the core. Confirm that boundary holds as the extractor is
  built.
