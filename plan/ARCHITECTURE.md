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
work. The engine owns clocks, I/O, asynchronous jobs and approval continuations.
Outputs render state; they do not interpret agent-specific input.
[Component behaviors](BEHAVIORS.md) defines the product rules.

## 2. Hooks and server

Hooks normalize supported Claude, Codex and Cursor events and fail open if Boop
is unavailable. Activity is distinct from a permission request. The server
checks live approval configuration before and after asynchronous ingestion.
Native approval is the default; Buddy interception requires global opt-in and,
for Codex, its additional opt-in. Disabling interception returns held requests
to the native flow. Passthrough does not mean permission granted by Boop.

The engine owns held continuations. First valid decisions win; stale IDs cannot
resolve new requests. Host expiry defaults to 290 s, below curl's 300 s and the
registered hook's 310 s. Managed installation removes only retired Boop MCP
entries. There is no active agent-expression endpoint.

## 3. Extractor and core

Deterministic readers turn bounded session context into lifecycle, runner,
outcome, topic and stakes events. Raw transcripts/tool arguments are not model
context or durable memory. Explicit errors drive Uh-oh; repeated commands and
silence do not imply failure. Duration drives effort and completion size.

The core chooses priority, three-second completion folding, fixed 60/120-second
nudges and XP award events. It never waits for model output. Approval decisions
do not award XP, bond or new memory facts.

## 4. Store and growth

SQLite persists reduced facts (30 days), profile, five traits, XP ledger and
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
opportunities at greetings, errors, idle after completion, and every five
minutes while idle/working without competing UI. Results are text or silence;
stale results are cancelled/discarded. Neutral greeting/error fallback remains,
otherwise silence. No daily inference quota exists.

Normal context includes state, effort, time/language, traits, XP/progress,
bounded factual history, three profile lines and twenty prior lines. No raw
paths, transcripts, approval decisions or drawings are supplied. Display text
is capped at 63 UTF-8 bytes, profile text at 240; bubbles last four seconds.
[Voice](UX-VOICE.md) specifies validation and context limits.

## 6. Personality and memory

After twenty minutes without activity, on AC power, reflection considers the
previous local day. The same guide/model receives at most 100 reduced facts,
twenty profile lines and current traits. It may return silence or up to five
memories with evidence IDs plus integer trait changes of at most ±3 per axis.
Store validates the whole update and persists it atomically, clamping values
to 0–255. Successful reflection is idempotent per day.

Invalid/unavailable output leaves profile and traits unchanged. There are no
fixed habit detectors, automatic bond awards or rule-generated candidates.
Evidence IDs establish references, not a semantic proof of truth. Model
reflection cannot alter XP, raw facts, state or permission handling.

## 7. Mac output

A static menu icon opens a transient 360 pt popover only when requested. Overview
contains status, requests, XP and sessions; Settings and Activity remain separate
panes. No ordinary desktop face or automatic state-triggered window appears.
Quiet mode mutes all sounds. Appearance and normal volume are fixed. Local PNG
sharing remains; there is no ranking service or network growth synchronization.
See [Mac UX](UX-APP.md).

## 8. Outputs and wire

`OutputProvider` consumes state changes. The device mapper derives RenderState
v2, with character-safe byte caps and bounded `nudgeRung`. [WIRE-V2.md](WIRE-V2.md)
is the field/command contract; [firmware protocol](../firmware/esp32/PROTOCOL.md)
describes the transport. BLE bonding and acknowledged OTA remain independent
of the removed leaderboard signing feature.

Device priority: system card → request → decision feedback → error bubble →
stats → bubble → overlay → face. Local firmware owns card arming, wake-press
consumption, hold gestures, shutdown, posture, dimming and offline snapshot
stats. The host owns approval authority and reminder timing. Repeated frames
do not replay a nudge. Quiet mode suppresses sound but preserves visual rungs.

## 9. Budgets and verification

| Path | Target/bound |
| --- | --- |
| Hook to device card | 500 ms target |
| Button to host decision | 300 ms target |
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
