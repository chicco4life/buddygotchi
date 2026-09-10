# Architecture

## 1. Data path and ownership

```text
hooks → Server → Extractor → Core → Outputs
                              ↕
                            Store
                              ↕
                            Voice ← BEHAVIOR.md
```

The reducer is pure: events and prior state produce the next state and pending
work. The engine owns clocks, I/O, asynchronous jobs.
Outputs render state; they do not interpret agent-specific input.
[Component behaviors](BEHAVIORS.md) defines the product rules.

## 2. Hooks and server

Hooks normalize Claude/Codex/Cursor activity and fail open. Approvals belong to
the editor. Hook v9 removes Boop permission interception registrations; the
script drains stdin and ignores stale PermissionRequest registrations. Config
loading removes old enablement keys. `/hook/approve` authenticates and returns
immediate passthrough for stale scripts, without ingestion or held continuations.
Legacy engine/device decision entry points are inert. No auto-approval or stakes
classification runs. Only reliable passive attention requests become cards;
activity and execution gates do not infer human waiting. Passive requests expire
after 290 seconds. Managed repair preserves unrelated hooks.


## 3. Extractor and core

Deterministic readers turn bounded session context into lifecycle, runner,
outcome and topic events. Raw transcripts/tool arguments are not model
context or durable memory. Explicit errors drive Uh-oh; repeated commands and
silence do not imply failure. Duration drives effort and completion size: under one minute has no cheer,
one minute hop, three minutes cheer, five minutes dance. Short completions still
earn XP and record outcomes. Working effort is light before three minutes.

The core chooses priority, three-second completion folding, fixed 60/120-second
nudges and XP award events. It never waits for model output. Approval decisions
do not award XP, bond or new memory facts.

## 4. Store and growth

SQLite persists reduced facts (30 days), profile, inactive legacy traits, XP ledger and
materialized earned totals. Existing historical inventory/moment records remain
readable but no new named moments or milestone keepsakes are created.

New awards are completed turn +3 and active local day +10. Materialized old XP
is frozen; a legacy-only ledger is migrated using its old formula once. Future
weight changes do not reprice earned totals. Streaks are consecutive active
local days with no rest-credit mechanism. The shared `wire` Swift package now
provides SQLite only; leaderboard and device-signing modules are removed.

The engine drains pending facts/awards through its asynchronous store queue.
Hook responses do not wait for a flush; shutdown and diagnostic reads do.
Profile lines are inspectable and deletable. Raw facts, accounting and retention
remain storage rules independent of what the model chooses to remember.

## 5. Markdown-guided behavior

`Voice` reads bundled `Resources/BEHAVIOR.md`, overridden by
`stateDir/BEHAVIOR.md`. Settings creates the override only if absent. Every
decision rereads it; invalid, empty or over-32-KiB overrides use the bundle.

Apple Foundation Models runs locally when available, using fresh sessions and
a five-second deadline. There is no cloud fallback. The engine offers dialogue
opportunities at greetings, errors and idle after celebration. There are no
periodic check-ins. Results are text or silence;
stale results are cancelled/discarded. Neutral greeting/error fallback remains,
otherwise silence. No daily inference quota exists.

Normal context includes state, effort, time/language, XP/progress,
bounded factual history, three profile lines and twenty prior lines. No raw
paths, transcripts, approval decisions or drawings are supplied. Display text
is capped at 63 UTF-8 bytes, profile text at 240; bubbles last four seconds.
[Voice](UX-VOICE.md) specifies validation and context limits.

## 6. Personality and memory

Personality is defined in BEHAVIOR.md. Familiarity comes from supported profile
memories and recent outcomes. Legacy numeric traits and counters stay stored
but inactive: no model input, daily drift, usual-hour sampling or project/session
familiarity updates. XP and greeting history remain independent and unchanged.

After twenty inactive minutes on AC power, daily reflection considers the
previous day. The guide/model sees at most 100 reduced facts and twenty profile
lines. It may choose silence or up to five evidence-backed memories. Store
validates/persists memories atomically and records daily idempotence. Invalid or
unavailable output leaves the profile unchanged. Old trait output fields are
ignored. Evidence references do not prove semantic truth; no raw paths,
transcripts, approval decisions or old named moments enter model context.


## 7. Mac output

A static menu icon opens a transient 360 pt popover only when requested. Overview
contains status, requests, sessions, device connection and compact XP, in that
order. Settings is a separate pane; Activity is removed. No ordinary desktop face or automatic state-triggered window appears.
Quiet mode mutes all sounds. Appearance and normal volume are fixed. Share-card export is removed; there is no ranking service or network growth synchronization.
See [Mac UX](UX-APP.md).

## 8. Outputs and wire

`OutputProvider` consumes state changes. The device mapper derives RenderState
v2, with character-safe byte caps and bounded `nudgeRung`. [WIRE-V2.md](WIRE-V2.md)
is the field/command contract; [firmware protocol](../firmware/esp32/PROTOCOL.md)
describes the transport. BLE bonding and acknowledged OTA remain independent
of the removed leaderboard signing feature.

Device priority: system card → request → error bubble →
stats → bubble → overlay → face. Local firmware owns passive dismissal, wake-press
consumption, hold gestures, shutdown, posture, dimming and offline snapshot
stats. The host owns reminder timing; approvals remain entirely in the editor. Repeated frames
do not replay a nudge. Quiet mode suppresses sound but preserves visual rungs.

## 9. Budgets and verification

| Path | Target/bound |
| --- | --- |
| Hook to device card | 500 ms target |
| State change to frame | 250 ms target |
| Model generation | 5 s deadline, asynchronous |
| Reflection | Off the interaction path; bounded evidence and output |

Physical latency targets need hardware measurement. Build and unit tests do not
close production BLE or live-editor gates. Use [Verification](VERIFICATION.md)
and [Plan](PLAN.md) for current evidence and remaining checks.

## 10. Repository and retained infrastructure

Active implementation lives in `app/` and `firmware/`; `archived/` is the previous
generation and is not extended. Retained infrastructure includes hook installer,
server, engine/reducer, BLE transport, OTA, firmware HAL and device tooling.
Independent development uses isolated app state/ports and a single hardware
writer; USB-only debug builds do not exercise production BLE and are never
published. See [device tooling](../tools/dev/README.md).

Earlier architecture discussions and phase-specific decisions are retained in
[architecture history](ARCHITECTURE-HISTORY.md). They do not override this
contract or the current component specs.

Growth has no live level calculation. The store aggregates daily completed-turn
units for the Mac activity grid; XP stays cumulative and existing awards persist.

## Device availability projection

Core derives `BuddyState.agentCounts` from the full session dictionary, independently of the six-item `activeSessions` preview. Working/thinking count as working; idle as idle; requests/errors as neither. ESP32 output encodes bounded `agents` rows and maps calm states to working/idle, suppressing device duration cheers and model bubbles for these sessions. Firmware owns the mixed-state dashboard transition and presentation; no new clock, I/O or view acknowledgment enters Core. Wire and frame budgets remain in WIRE-V2.md.
