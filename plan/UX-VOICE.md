# UX: Model-driven buddy behavior

The local LLM directs the buddy's dialogue, personality evolution and memory selection. One Markdown guide
sets what deserves a response, what is worth remembering and when to stay quiet.

## Steering

The shipped default is [BEHAVIOR.md](../app/Boop/Resources/BEHAVIOR.md).
**Settings → Edit buddy behavior…** creates and opens `~/.boop/BEHAVIOR.md`
(or `BEHAVIOR.md` inside `BOOP_STATE_DIR`). It never overwrites an existing
file. Each decision rereads it; no rebuild or restart is needed. Missing,
empty, unreadable, invalid UTF-8 or over-32-KiB overrides use the bundled guide.
The guide is trusted owner configuration; runtime context is supplied as data.

## Ownership

| Owner | Decisions |
| --- | --- |
| Deterministic core | State, effort from task length, celebration size/timing and 3 s folding, XP, approvals, nudge ladder and display priority |
| Local model + Markdown | Dialogue/silence, tone, learned memories and trait changes |
| App scheduler/display | When a decision is possible; cancellation, byte budget and bubble expiry |

Dialogue returns **a line** or **silence**; private reflection can propose
evidence-backed memories and bounded trait changes. The model has
no tools, state setter, approval authority or drawing channel. Future optional
actions can extend this boundary without moving state truth into the model.
Approval cards, system labels and critical instructions remain deterministic.

## Decision loop

1. Offer context on a return greeting, explicit error, or a completed turn after its
   celebration ends in idle.
2. Every five minutes, offer a periodic opportunity while idle or working,
   only without a prompt, existing bubble or affection overlay. An event
   opportunity restarts this interval. Skipped checks are not queued.
3. Supply the guide plus state, session count, effort, available completed-task
   duration, time bucket, language, known agent, traits/bond, XP/level/streak/task totals, a bounded memory
   summary, up to three profile lines and up to 20 prior lines. No raw transcript or tool arguments.
4. The model returns a line or `SILENT`. Silence creates no bubble or fallback.
5. Accept displayable text; discard late results after state/card changes,
   replacement requests, language/runtime changes or shutdown. A bubble lasts
   four seconds and never overrides an approval or wakes a sleeping buddy.

Completion text is considered only after the animation finishes and the buddy
returns to idle. It cannot delay, resize, cover or restart the celebration. If
work or an approval interrupts that idle period, its pending reply is discarded. No gifts,
recaps, completion stories, inferred failures or agent-authored MCP return.
Nudge dismissal changes the reminder rule silently; no scripted hush remark.

## Runtime and fallback

Apple Foundation Models runs locally on supported macOS 26+ systems when
available. There is no cloud fallback or bundled llama.cpp model. Each request
uses a fresh session, temperature 0.4, and a five-second asynchronous deadline.
Device and profile requests have separate generation lanes. A busy/unavailable
lane, failed generation or invalid reply uses a minimal fallback:

- Greeting: one neutral English/Korean greeting, then silence if already used.
- Error: one neutral English/Korean error line, then silence if already used.
- Completion and periodic opportunity: silence.
- Reflection: no memory or personality changes.

Device text is capped at 63 UTF-8 bytes, profile text at 240, on character
boundaries. Code rejects control characters and unsupported languages; tone,
capitalization, punctuation and word choice live in the guide. Exact repeats
from today or the last 20 stored lines are excluded. Share cards retain their
separate authored captions.

The model is responsible for using supplied facts faithfully; display validation
is not a semantic proof. Reflection validates evidence IDs and bounds, not the meaning of a memory.
Quiet mode mutes sound only. No daily inference quota or speech quota exists;
periodic cadence and generation deadlines are scheduling/latency controls.

## Stats and memory inputs

Energy, cheek, warmth, curiosity, bond, XP and remembered history are context
for the same model, interpreted through BEHAVIOR.md. They do not select a
mandatory conversational response. Accounting and storage stay deterministic.

Each normal behavior request includes `progress` (XP, level, XP to next level,
current/best streak, active days together, completed tasks and today's
XP) and `memory` (completed turns, lifetime sessions, known-project count, and
up to five recent factual outcomes/durations and dates, plus legacy moments). Usual-hour familiarity is omitted until
20 samples span at least 14 days. Up to three profile lines remain included.
Reflection receives at most 100 reduced facts from retained history, up to 20
profile lines and current traits. It uses the same freshly read guide.

History retrieval reads at most twenty stored outcome/completion/error/moment rows and exposes at most
five eligible facts. No raw project identifiers/paths, transcripts, token
counts, approval decisions or retired drawings are supplied. Stored records
and numeric inputs do not grant authority to change XP, base states or approvals.

## Markdown-guided learning contract

At the existing daily reflection opportunity, return SILENT or JSON containing
`memories: [{line, evidence: [id]}]` and `traits: {axis: delta}`. Memory selection
and trait evolution are model/guide decisions; rule-derived candidates and
DailyDrift are removed, including automatic active-day/greeting bond rewards.

At most five memories, each ≤240 UTF-8 bytes with valid supplied evidence IDs;
only energy, cheek, warmth, curiosity and bond can change, by integers ±3 per
day and within 0–255. Unknown axes, invalid evidence, malformed JSON or oversized
output invalidate the whole update. Empty updates are valid. Stored facts, XP
and approval decisions cannot be changed. The model must ground claims in
facts; numeric validation is not a factuality proof. Unavailable models and
five-second timeouts preserve existing profile and traits. Successful reflection
is idempotent per local day. Private reflection does not create a bubble.
