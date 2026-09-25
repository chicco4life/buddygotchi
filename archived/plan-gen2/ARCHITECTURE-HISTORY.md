> Historical record through 2026-09-11. This document includes superseded behavior; use [ARCHITECTURE.md](ARCHITECTURE.md) for the current contract.

# Architecture

## Help simplification — 2026-09-10

Owner decision: remove inferred stuck and hungry/rate-limit personality,
completion gifts/collection, daily recaps, teach moments and obsolete quick
commands. Preserve explicit errors, completion celebrations with 3 s folding,
XP history, reflection, and approval infrastructure. Greetings and errors retain
local/authored dialogue. Agent expression and drawings are deferred to IDEAS.md; no active channel remains. Historical
records remain readable. This supersedes removed-feature descriptions below;
implementation and verification are tracked in PLAN.md.


## Settings policy revision — 2026-09-10

The desktop now fixes sound volume to step 1 and initializes dialogue automatically (local model with authored fallback). Legacy saved volume and Voice choices are ignored. Store projects default skin, no accessory and default silhouette, preserving old metadata and inventory without exposing customization. Retired quick and collect commands are ignored. Settings has one local diagnostic export action and no reset/retirement actions. Wire shapes remain compatible.

Status: v1 target architecture, second draft, 2026-09-08. Implements
`VISION.md`, `UX-DEVICE.md`, and `IDEAS.md` idea 1. The current codebase is
described in `archived/research/eng/ARCHITECTURE-APP.md`; §10 says what is kept from
today and what is new.

---

## 0. The whole system in one picture

```
 Claude Code      Codex        Cursor
     │               │            │          local hooks; fail open
     ▼               ▼            ▼
 ┌────────────────────────────────────┐
 │  hook script                       │  caps bytes, POSTs to localhost
 └────────────────┬───────────────────┘
                  ▼
 ┌──────────────────────────────────────────────────────────────┐
 │  Mac app                                                     │
 │                                                              │
 │   Server ──► Extractor ──► Core ──────────────► Outputs      │
 │   routes     per-session   engine + pure        desktop      │
 │   auth       transcript    reducer; state,      device ──► BLE
 │              window        duration, cheer size               │
 │              (memory only)      │    ▲                       │
 │                                 ▼    │                       │
 │                          ┌──────────────┐   ┌──────────┐     │
 │                          │  Store       │   │  Voice   │     │
 │                          │  facts,      │──►│  local   │     │
 │                          │  profile,    │   │  model + │     │
 │                          │  traits, XP  │   │  fallback│     │
 │                          │  nightly job │   └──────────┘     │
 │                          └──────────────┘                    │
 └──────────────────────────────────────────┬───────────────────┘
                                            ▼  Nordic UART, newline JSON
 ┌────────────────────────────────────────────────────────────┐
 │  Buddy firmware: parse → model → render six states;        │
 │  buttons, motion, sound, travel stats, NVS, OTA            │
 └────────────────────────────────────────────────────────────┘
```

Four things in the app: **Server**, **Extractor**, **Core**, **Outputs**.
Two services beside them: **Store** and **Voice**. That is the whole list.

---

## 1. Principles

1. **Pure core.** The reducer takes state and an event and returns state. No
   I/O, no clock, no model calls. Time arrives on events and as ticks.
2. **Thin device.** Firmware renders what the app sends and reports inputs.
   It never composes text or decides anything. In travel mode it displays a
   snapshot it was given.
3. **Fail open.** App down: hooks exit zero and the agent continues
   natively. Device gone: the app carries on. Model slow: authored lines.
4. **See, extract, forget.** Raw transcript content lives in memory only,
   bounded per session, evicted on session end or size. It is never written
   to disk, never logged, never sent to the model.
5. **One wire contract.** Every display derives from `BuddyState`. The
   device is the display that happens to be over Bluetooth.
6. **Local behavior and growth.** No leaderboard or growth synchronization.
   Model download and firmware updates retain their separate delivery paths.
7. **Utility never waits on expression.** Needs-you and approval paths do
   not depend on Store or Voice.

---

## 2. Hooks and the script

One bash script registered in each agent's hook config, plus the small
Cursor helper. The installer writes, verifies, and repairs the config.

Events subscribed, mapped to one internal vocabulary:

| Internal | Claude Code | Codex | Cursor |
| --- | --- | --- | --- |
| session start / end | SessionStart, SessionEnd | SessionStart, SessionEnd | sessionStart, sessionEnd |
| turn start | UserPromptSubmit | UserPromptSubmit | beforeSubmitPrompt |
| tool call | PreToolUse | PreToolUse | beforeShellExecution, beforeMCPExecution, afterFileEdit |
| tool result | PostToolUse, PostToolUseFailure | PostToolUse | afterShellExecution, afterMCPExecution, postToolUseFailure |
| needs you | PermissionRequest, Notification | PermissionRequest (separate opt-in) | No authoritative waiting event; before* hooks are activity only |
| turn end | Stop, StopFailure | Stop | stop, afterAgentResponse |

The script forwards: event, session id, cwd, tool name, full tool input,
exit status or error class, the first and last 1 KB of tool output, the
prompt text on turn start, and the agent's closing message on turn end.
Body capped at 16 KB. Fail-open at the script: short timeout, always exit
zero, approvals return passthrough if the app cannot answer.

---

## 3. Server

Localhost HTTP with a per-install token. Routes: `/hook/event` (returns
immediately), `/hook/approve` (holds until decision or timeout, returns
allow, deny, or passthrough), `/hook/signal` (Cursor helper), `/healthz`. The server authenticates, parses the
per-agent shape into a `RawHookPayload`, and hands it to the extractor. It
holds no state. The Cursor auto-approve rule for read-only shell commands
stays here because it must read the full command.

---

## 4. Extractor

Turns capped hook payloads into lifecycle events and reduced facts. A session
window holds project identity, counters, a capped closing line and at most
400 pending calls (tool, recognized runner, optional call ID). Results match
call IDs where available; otherwise tool name. There is no transcript archive,
goal signature, retry tally, edit counter or token accumulator.

Runner recognition covers test/build/lint/typecheck commands. Outcome comes
from exit status, then runner output patterns, otherwise unknown. Each result
can become a factual tool outcome. Stakes remain deterministic; displayed text
is the supplied reason or tool name. Prompt text and file extensions reduce to
allowlisted tone/topics, not raw stored text. Closing text is capped at 120
characters in memory and is not consumed by reflection.

Effort and celebration size belong to Core and depend only on work-period
duration. Unknown schemas degrade to lifecycle-only once per source. Session
end drops the window. Corpus coverage and a full byte-bound remain verification
gates; deleting retry/edit maps reduces retained state but does not prove them.

---

## 5. Core

**Engine.** The orchestrator: owns the clock and ticks, receives events
from the extractor, device, and UI, runs the reducer, calls Store and
Voice, and fans state to outputs. Held approval connections live here.

**Reducer.** One pure function. It owns:

- **Sessions.** Per agent session: source, project, state, tool, effort,
  pending prompt.
- **The six states** with parameters, collapsed across sessions by
  priority: needs you > uh-oh > done > working > idle > asleep. One
  creature.
- **Nudge ladder timing,** fixed 60/120-second rungs, current-request snooze, quiet sound gating.
- **Duration-only celebrations** with three-second folding.

**BuddyState.** The public projection: the creature's state and
parameters, session dots, the pending card, the current bubble, greet level, focus, and the growth snapshot.

### Factual behavior context

No named moment detectors, retry tallies or learned mood overrides. Extractor
records tool outcomes; Core records completed-turn durations. Store projects
at most five recent facts for the Markdown-guided model. Historical moments
remain readable without triggering behavior. Effort and celebration size share
the 10/25-minute duration boundaries. No-session state is always asleep unless
a higher-priority transient state is active.

---

## 6. Store

One SQLite database and one background job. Called by the engine; results
return as events so the reducer stays the single source of truth.

| Table | Holds | Retention |
| --- | --- | --- |
| facts | Tool outcomes, turn durations, themes, tone, error classes, session summaries; historical moments | 30 days |
| profile | Human-readable lines with source and confidence | Life of the buddy; deletable line by line |
| traits | Four personality axes plus hidden bond | Life of the buddy |
| ledger | Append-only XP source units and materialized earned totals; historical awards are frozen | Life of the buddy |
| inventory | Historical item timestamps and keepsakes; no new milestone detector | Life of the buddy |

**Nightly job.** After 20 minutes without activity and on AC power, process
the previous local day once. Voice reads BEHAVIOR.md and proposes up to five
evidence-backed memories plus bounded changes to all five traits. Store validates
and persists atomically; invalid/unavailable output leaves data unchanged. No
rule-derived candidates, fixed trait drift or automatic bond rewards remain.
Reflection consumes bounded reduced facts, not the extractor closing line.

Clearing the profile deletes its lines; name, level, and bond stay. Profile
reads come from Store and do not emit a reducer event.

Phase 4 implementation: `growth_totals` caches daily source XP and units in
the same transaction as ledger awards. Formula changes rebuild this derived
cache from the append-only ledger; normal snapshots read the rollup, including
today. Accepted turn units retain the rolling-hour cap across midnight.
`memory` holds one Codable `PetMemory` JSON row. Engine bootstrap constructs
Store and runs legacy migration off the main thread; unreadable legacy files
are preserved with an `.unreadable` suffix. Reducer transitions emit pending
awards and facts, which the engine drains onto its asynchronous store queue.
Hook responses do not flush that queue; shutdown and diagnostic reads do.

---

## 7. Voice

**Behavior controller.** `Voice` makes local-model decisions from a live-read
`BEHAVIOR.md` and a structured snapshot. The model chooses text or silence on
greetings, errors, idle after a completed celebration, and periodic idle/working
opportunities. The
engine supplies opportunities every five minutes without blocking the reducer;
event requests restart that interval. Rules retain state, effort, celebration,
XP, approvals and nudge authority. Text is a transient, cancellable output.

The bundled Markdown is the default; `stateDir/BEHAVIOR.md` overrides it without
a rebuild. Settings creates/opens this override only on the edit action. The
32-KiB reader rejects invalid overrides in favor of the bundle. Prompt style,
occasion guidance and silence preferences belong in that file. No register-based
greeting/error banks, lead-in selection or lexical style blacklist remains.

Model calls have a five-second asynchronous deadline. On failure use a neutral
greeting/error or silence; profile reflection retains its candidate. Display
validation caps text and rejects controls. Details and context fields are in
[UX-VOICE.md](UX-VOICE.md). Share-card captions remain a separate authored bank.

---

## 8. Outputs and the wire

`OutputProvider` stays: `start`, `stop`, `stateDidChange(prev, next)`.

**Desktop.** Menu bar creature and popover with the same six states and
cheer sizes as the device; the needs-you card, profile page,
settings, onboarding; sounds when no device is paired.

**Device.** A mapper from `BuddyState` to `RenderState v2` with byte caps
on character boundaries, and the BLE transport: a frame on every change, a
keepalive every few seconds, inbound commands, and the existing acked
chunk protocol for updates.

### RenderState v2 and device commands

[WIRE-V2.md](WIRE-V2.md) is the single source of truth for both directions,
including field names, byte caps, compatibility, and frame shedding.

### Transport

Nordic UART over BLE, newline JSON, 180-byte chunks, LE Secure Connections
bonding, as today. A minute without frames is link lost on the device.

---

## 9. Firmware

```
 line ──► parse ──► validate ──► device model ◄── buttons, IMU, battery
                                     │
                                     ▼
                     renderer by priority: system card > needs-you card >
                     decision feedback > uh-oh bubble > stats > bubble >
                     overlay > face + field + dots + orb
                                     │
                                     ▼
                     face parts, field, sparks, sound (completion/interaction motifs and nudge reminder)
```

- **Messages.** One line, one parse, one validation. Unknown keys ignored,
  bad enums keep the last good value, frames never block a render tick.
- **Local autonomy,** exactly what must work without the app: card arm
  delay and wake-press guard, shutdown hold ladder, posture from the IMU,
  dim ladder with a never-off sleep frame, boop and pet, shake and flip,
  travel stats from the last snapshot.
- **NVS.** BLE bond, last snapshot, cosmetic ids, volume, first-wake
  flag. Nothing else.
- **Rendering.** Per-frame incremental, springs for squish and dangle,
  parts compose; no sprite per state.
- **Updates.** OTA over the acked protocol; board id in the status reply
  so the app never sends the wrong image.
- **Debug.** USB serial mirrors the BLE line protocol for hardware-in-the-
  loop tests, as today.

Removed from today's firmware: species and character menu, glance card,
orb-per-session fireflies, mood engine, any text composition.

---

## 10. Kept, changed, new

| Area | Today | v1 |
| --- | --- | --- |
| Hook script, installer, server routes, auth, Cursor auto-approve | Keep | Forward more fields with caps |
| Extractor with session windows | Hints parsed inline | New |
| Engine and pure reducer | Keep | Six states, duration-only cheer sizing |
| PetMemory | Keep the idea | Becomes Store: SQLite, profile, ledger, nightly job |
| Voice | New controller | Markdown-driven local decisions, minimal fallback |
| MCP agent channel | Deferred | No endpoint; enhancement in IDEAS.md |
| Desktop output | Keep | Re-render for six states; profile page, onboarding |
| RenderState, BLE, OTA | Keep the mechanism | v2 fields, new inbound commands, board id |
| Firmware | Keep HAL, BLE, OTA, HIL | Rewrite model and renderer around six states |

---

## 11. Flows end to end

**Needs you.** Hook fires, script holds `/hook/approve`. Extractor emits
needs-you with gloss and stakes. Reducer enters the state; engine holds the
continuation. Frame with the card reaches the device under 500 ms. Firmware
arms, plays "meep?". Tap sends `decision` and reaches the app under 300 ms.
Engine resolves the held call with allow; the next frame clears the card;
firmware shows "yes!" only then. Timeout or app gone: passthrough.

**The tenth try.** Each recognized tool result produces a factual outcome,
without counting retries or awarding XP. A completed turn earns 3 XP and a
celebration determined only by its duration. The first active local day earns
10 XP. The model may refer to recent factual history; no story is forced.

**Unlink and back.** Every frame carries `snap`; the device keeps the last
in NVS. Link lost on battery: a minute at the Bluetooth mark, yawn, travel
idle; stats render from NVS. Link back: device sends status and battery;
app sends greet with the level from the gap.

**Nightly.** Idle and on power: Store reads the day's facts and the
closing-line summaries, Voice proposes profile lines and trait deltas,
caps apply, events go through the reducer, the extractor drops the
closing lines.

**First wake.** First-wake flag unset: firmware plays the ritual and shows
the Bluetooth mark. App bonds and sends a frame; the mark goes solid. First
agent event: frame carries the first color; first turn end is a cheer
regardless.

---

## 12. Budgets and storage

| Path | Budget |
| --- | --- |
| Hook to card on device | 500 ms |
| Button to decision at the app | 300 ms |
| State change to frame | 250 ms |
| Authored line | instant |
| Model behavior decision | 5 s asynchronously, then minimal fallback/silence |
| Nightly job | minutes, off path |

| Lives on | What | Retention |
| --- | --- | --- |
| Mac, memory only | Session transcript windows | Bounded; gone on session end or app quit |
| Mac, SQLite | Facts, profile, traits, local XP ledger, historical inventory | Facts 30 days; the rest for the buddy's life |
| Mac, files | Behavior guide, share captions, runner table, stakes rules | Shipped; guide supports a local override |
| Device, NVS | BLE bond, snapshot, cosmetics, volume, first-wake flag | Until replaced |

No transcript, code, file content, or prompt text is written to disk
anywhere, in any form.

---

## 13. Testing

- **Reducer.** Pure unit tests: collapse across sessions, duration boundaries,
  cheer sizing, nudge timing, and no inferred stuck state.
- **Extractor.** Fixture corpus of real hook streams per agent and version,
  replayed through windows, asserting events and facts. The guard against
  agent releases.
- **Behavior.** Live Markdown reload, explicit silence, periodic eligibility,
  late-result cancellation, display caps and fallback deadline tests.
- **Wire.** Byte-cap encoder tests on character boundaries; compatibility
  against the previous firmware.
- **Firmware.** Hardware-in-the-loop over USB, as today.
- **End to end.** Scripted sessions per agent against a running app,
  including the tenth-try case.

---

## 14. Open questions

- Verify a byte bound for the capped pending-call context; no goal history is retained.
- Model runtime, MLX versus llama.cpp, decided by a latency bench on the
  Macs the audience owns.
- Windows changes the script, the server host, and the runtime, and
  nothing in the core. Confirm as the extractor is built.

## 15. Architecture review, 2026-09-09

Shared pure policies belong in Core: `CardStakes.swift` supplies the risk
classifier to both extraction and reducer fallback; `UTF8Text.swift` supplies
character-safe byte truncation to input parsing, Voice, UI, and wire encoding.
Neither helper belongs to the ESP32 output implementation. Their algorithms
and wire behavior are unchanged. See [ARCHITECTURE-REVIEW.md](ARCHITECTURE-REVIEW.md)
for the remaining staged simplifications and preservation gates.

### Local growth accounting — 2026-09-11

Store awards only completed turns and active days. Existing materialized XP
is frozen. A migration-only legacy formula reconstructs old ledger-only stores
once; subsequent reads, formula edits and backdated entries never reprice old
awards. Legacy source enums/tables remain readable, with no active signing
or sync. No rest credits, milestone detectors or hourly XP caps remain.

### Transient voice and device preferences

`TransientVoiceTasks` owns the bubble task slot, cancellation, and
revision checks. Replacing or canceling one lane leaves the other intact.
The engine supplies generation and delivery callbacks, keeps prompt suppression
at delivery, and cancels both lanes for stop, language/runtime changes, and
retirement. `finishPendingWork` still waits
for the current bubble work after extraction and persistence.

`ESP32Output` receives its preferences from the composition root. Saved-device
lookup, unpairing, and both normal and test-celebration frames use that instance.
Preview/snapshot output instances receive their scratch preferences too. Frame
encoding still uses the same v2 keys, caps, and shedding policy.

### Canonical creature projection

`BuddyState` stores species independently and derives `pet`, `lastSignal`, and
`celebrateIntensity` from `creature`. Reducer aggregation no longer writes those
three projections. `BuddyState+Encoding.swift` preserves the established
36-field diagnostic shape, including species nested under `pet`, and omits nil
optionals as before. Prompt, effort tier, and greeting metadata remain stored
because they carry information not recoverable from the creature projection.
There is no database migration or device wire change.


### Physical motion verification tooling (2026-09-10)

`tools/webcam` is a standalone macOS verification utility outside the shipping
app and firmware. AVFoundation records one explicitly selected camera without
audio for at most 60 seconds. Offline decoding emits original frame timestamps
and cropped consecutive-frame sheets for a bounded review interval. Capture
cadence diagnostics are separate from the reviewer’s motion verdict; the utility
never reports an automatic animation pass. It does not change the wire contract
or own device control. Existing `buddyctl` commands drive optional USB scenarios
with BLE writers absent and the presentation clock running. See
`VERIFICATION.md` §2.1.1 for evidence and capture-quality requirements.


### XP-independent availability (2026-09-10)

XP and levels are statistics, not prerequisites. `CompanionOption.catalog`
defines universally available options; Store inventory projects missing catalog
entries alongside historical rows, and equip validates catalog membership only.
Growth no longer grants cosmetics. Existing XP, equipped selections, historical
timestamps and keepsakes are preserved without a schema change. Behavior and
wire formats do not change; level-up effects remain milestone acknowledgments.

### Mac menu bar companion (2026-09-10)

Owner-directed replacement of the regular control-center window: AppDelegate owns
one transient NSPopover attached to an NSStatusItem. ControlNavigation selects
Overview, Activity, Settings or explicit setup inside it. The app uses accessory
activation policy and never auto-opens UI on launch or state changes. Legacy
interactive-mode preferences are ignored. Settings uses one grouped Form with all sections expanded. Profile rows are
embedded in that form without a nested scrolling list. There is no settings
category navigation state. Approval presentation is scoped to Overview; changing
panes neither resolves requests nor overlays them on Settings, Activity or setup.

The overview exposes growth and session state without a creature. The XP bar is
within-level earned XP divided by that level's interval. Recent XP history remains
bounded to 60 positive daily/source totals, read after the persistence barrier.
No transcript text is added to growth history.

Quiet mode reuses the inverted soundsEnabled preference and the legacy
focusToggled event / creature.focus field. The reducer no longer gates the visual
nudge ladder on that flag. Startup restores it from soundsEnabled; old Focus-hour
preferences are ignored. The engine persists physical-device toggles too. The
frame sends mute=0 in Quiet mode, preserving the selected volume in preferences;
firmware treats focus as sound-only and removes its visual marker and error-sound
exception. No state, animation phase, XP, or approval decision changes with Quiet
mode. See WIRE-V2 and firmware PROTOCOL for the compatibility names.

### Parallel development isolation (2026-09-10)

`tools/dev/instance.py` owns per-worktree headless lifecycle: unique loopback
port/token, config and store directory, preferences suite, logs and PID metadata.
`BuddyConfig` reads and writes the selected state directory's config. Headless
instances never install global hooks or create Bluetooth outputs. E2E clients
receive explicit instance configuration. Live-hook doctor remains an exclusive
shared-endpoint diagnostic with its separate legacy launcher.

`tools/dev/device.py` reserves the single physical device across setup, scenario,
and restoration. A machine-wide advisory lease is shared with buddyctl and HIL.
The GUI must be quit to release BLE before reserving and manually relaunched
later; the wrapper rejects a running GUI. Firmware setup requires a restoration
script. No simulator or wire change. See `tools/dev/README.md` for limits.
Headless startup uses a state-directory instance lock and bypasses the GUI
bundle-instance check; the normal GUI retains its machine-wide singleton guard.


## Compact device footer, 2026-09-10

Device rendering ignores dots/dotAlert, retaining validation and the wire fields for compatibility. Landscape approval footer is 88 px high with prompt left and instructions right. Approval timing and transport are unchanged.


## USB-only bench verification, 2026-09-10

USB bench builds use the separate ws-amoled164-usb-debug environment with BOOP_USB_ONLY. Its BLE bridge is compiled to no-op functions; it never initializes Bluetooth or modifies bond storage. Normal shipping builds retain the existing bridge. No app lifecycle, timers, settings, or runtime debug mode are added. USB ping reports usbOnly for verification tooling.


## Larger approval face, 2026-09-10

The compact landscape approval/decision face uses a 25 px lift and 1.2× eye dimensions, interpolated by card progress. System-card lift remains 47 px. Footer positions and button behavior are unchanged.

### Deferred companion features — 2026-09-11

Leaderboards, network growth sync and device signing are removed, alongside
agent drawings. Local share-card export remains. Enhancement ideas live in
IDEAS.md; earlier phase evidence records their historical implementation.

## Hook approval correction (2026-09-10)

Hook v8 leaves Codex PermissionRequest to its native approval flow by default,
even when the global Boop approval mode is enabled. Both `approvalMode` and
`codexApprovalMode` must be true to hold a Codex request. Missing opt-in means
no HTTP post and no passive waiting card: this event precedes the native flow
and does not prove the automatic reviewer needs a human. Ordinary activity
continues through PreToolUse and PostToolUse. There is no authoritative hook
for a later native Codex reviewer escalation, so native-mode approval waiting
is not mirrored. Claude Code retains its existing PermissionRequest routing;
Cursor before-execution events remain nonblocking activity.

The transport retains event aliases, call IDs, error classes and input aliases
through output capping. Codex now registers SessionEnd. Approval descriptions
are transient card text (200 UTF-8 bytes before existing device caps); stakes
and auto-approval classify the actual operation independently of that text.

### Shared model inputs — 2026-09-11

Normal behavior requests carry current growth plus a `BehaviorMemory` projection
alongside traits and profile. The projection contains counts, optional usual-hour
familiarity, and up to five recent factual outcomes/durations and legacy moments from at most twenty stored
fact rows. It excludes raw identifiers, tool output, approvals and retired
agent drawings. The engine refreshes cached moments with voice context after
persisted awards; each request reads the latest projected growth and pet memory.

These are descriptive inputs for Markdown-guided decisions, not independent
conversation controllers. Ledger, drift, reflection candidate extraction, state
and celebration rules remain authoritative. Model output remains text/silence.
Denied approvals no longer emit memory facts or contribute to trait drift.

## Native approval default — 2026-09-11

Config, hook script and Cursor helper default to native approvals. The server
also gates `/hook/approve` on live opt-in before intercepting or auto-approving;
Codex requires its separate switch as well. Recheck after asynchronous hook
extraction. A disabled/stale caller receives native passthrough. Enabling Buddy
can replace the native dialog; the Settings explainer states this explicitly.
