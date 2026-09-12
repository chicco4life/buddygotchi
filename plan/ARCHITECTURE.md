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
silence do not imply failure. Working effort is light before three minutes, hard
until five, then grinding. Completion presentation uses guide policy: <3 seconds
face, 3–<20 seconds caption, >=20 seconds full. All started completions still
earn XP and record outcomes; historical effort accounting is unchanged.

The core chooses priority, bounded moment coalescing/cooldown, fixed 60/120-second
nudges and XP award events. It never waits for model output. Approval decisions
do not award XP, bond or new memory facts. `BuddyReducer.swift` owns mutations;
`BuddyProjection.swift` derives display priority, ordered Mac rows, device rows,
and counts from the resulting state. Both remain pure.

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
opportunities on starts, completions, bounded long-work milestones, person
returns and explicit errors. Results remain text or silence;
stale results are cancelled/discarded. Every display opportunity may be silent;
optional immediate fallbacks are supplied by the same guide, never firmware
phrase lists. Error remarks have no stock fallback. No daily inference quota exists.

Display decisions share `BehaviorContext`: the whole desk, optional event,
previous scope and five recent remarks. `WorkContext` groups canonical local
project identities and bounds JSON to 6 KiB; `BehaviorTasks` serializes display
calls with a two-second scope debounce and priority for existing remarks.
First/latest hook intent (768 bytes each) is memory-only, an explicit exception
to the old no-prompt model boundary. No extra model or transcript reader exists.
The reducer projects persistent `workScope` for Mac only via `workScopeChanged`.
Scope is capped at
120 bytes without truncation and discarded on
scope/runtime changes. Display requests use English independently of UI language;
UI language changes preserve scope and pending display replies. It never enters SQLite. Legacy private reflection
remains independent; richer evidence-backed result/callback stages are pending.
[Voice](UX-VOICE.md) specifies validation and context limits.

## 6. Personality and memory

Personality is defined in BEHAVIOR.md. The existing profile/reflection storage
remains, but the new shared display context does not yet supply the learned profile or episodic memories. Legacy numeric traits and counters stay stored
but inactive: no model input, daily drift, usual-hour sampling or project/session
familiarity updates. XP remains independent. A backward-compatible optional `lastInteractionAt`
persists actual turn-start/boop interaction for returns, separate from background
`lastSeenAt` accounting.

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

Device priority: display off → system card → request → error bubble →
stats → thread table → legacy completion notice → bubble → moment → overlay → face. Local firmware owns passive dismissal, wake-press
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

Core derives `BuddyState.agentCounts` and all `activeSessions` rows from the full
session dictionary. The Mac scrolls the complete list; the independent device
preview is bounded only at encoding. Working/thinking count as working; idle as
idle; requests/errors as neither. ESP32 output maps calm states to working/idle
and suppresses desktop duration cheers while preserving eligible model bubbles.
The earlier blanket bubble suppression contradicted the dialogue contract and
made ordinary companion remarks disappear whenever a session existed; the
quality pass removes that suppression while firmware retains layer priority. Core owns completion batching/cooldown; firmware owns local notice deadlines and explicit thread-page navigation; no new clock, I/O or view acknowledgment enters Core. Wire and frame budgets remain in WIRE-V2.md.

## Thread metadata and completion presentation

Core owns the completion sequence, batching, cooldown and recent history;
firmware converts age/remaining duration to local presentation deadlines. Reconnect
establishes a baseline without replaying old notices. Details/controls and all
presentation timings are in [Device UX](UX-DEVICE.md); shared completion rules are
in [Behaviors](BEHAVIORS.md#3-effort-and-celebrations).

Use explicit hook thread/session titles when supplied. At Codex session/turn
boundaries, read matching title metadata from at most the last 256 KiB of its
local session index, off the main actor. Otherwise use project plus short stable
session ID. Never read transcripts or display raw prompt/command text as titles.
Names are ephemeral display metadata, never model memory. UTF-8 titles are
bounded to 47 bytes. The preview contains up to 12 sessions in stable ID order
and 6 recent completions; encoding may shed rows while retaining total counts.
There is no persistent Last finished footer; history remains in detail pages.

## Shared turn-moment projection

`BuddyBehaviorGuide.policy()` reads one validated `boop-policy` JSON fence from
the existing Markdown, using bundled defaults when missing/invalid. The engine
supplies that value to pure Core; `updateTurnMoments` detects starts/completions,
consumes bounded stale-tick milestones, merges returns, coalesces and expires.
Terminal failure closes the active duration while retaining its original start
separately for error ordering; a retry cannot inherit failed work duration.
`TurnMoment` carries ID, kind, tier, expression, text, count, deadline and bounded
event facts. `momentText` validates asynchronous results against ID/count/deadline.

Existing `BehaviorTasks`/`Voice` handles all text in its one display lane; no new
occasion service or model worker. Event context adds elapsed/absence milliseconds,
local hour/time-of-day, title, count and explicit neutral outcome evidence.
Presentation expressions are a small enum selected by Markdown policy; the model
still returns text or SILENT. Animation primitives are firmware code.

The additive v2 `moment` field sends identity, tier, expression, text, count and
age/left. Firmware enforces local expiry, no replay and actual glyph fit. Scope
is omitted by the host; old `scope` remains parsed for compatibility but invisible.
The newline-inclusive 1536-byte frame cap and shedding order remain unchanged;
snapshot/cosmetics/history preview can be shed while moment identity is retained.
See [Turn moments](UX-TURN-MOMENTS.md), [Wire](WIRE-V2.md) and [Device UX](UX-DEVICE.md).

## Firmware update coordination

`FirmwareUpdater` uses `FirmwareReleaseProviding` and `FirmwareUpdateTransport`
boundaries so asynchronous checks, transfer failures and reconnects can be tested
without network or Bluetooth. New checks invalidate older results; cancellation
cannot let an old transfer overwrite a retry. A commit acknowledgment or
post-commit disconnect enters version confirmation, never optimistic success.
A fresh device status must match the offered version (optional `v` prefix ignored).
Confirmation has a 45-second budget from commit submission; mismatch or missing
confirmation becomes a recoverable failure. Automatic reconnect checks preserve
the terminal result. Dismissing a failed check does not assert "up to date".

## Readiness boundary checks

The display boundary masks recognizable private strings before generation and
rejects private echoes and repeated remarks afterward. Scope without any intent
returns silence without generation. These are structural safeguards; the model
still owns semantic interpretation. Guided-generation experiments live only in
the test replay, outside the production runtime.

Firmware downloads require HTTP 2xx before decoding a manifest or verifying a
binary hash. Cached manifests are keyed by their source URL; legacy entries
without a source are refreshed. Codex SessionEnd registration uses its 3-second
limit; other lifecycle hook registrations retain their existing timeout.
