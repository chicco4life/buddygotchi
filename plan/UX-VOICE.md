# UX: Model-driven buddy behavior

Companion summaries and remarks are English-only in the first version. Context
uses `language: "en"`; changing the app UI language does not cancel, clear or
regenerate companion text. Private legacy reflection retains its language setting.

Owner simplification: keep event-based dialogue and evidence-backed memory.
Remove periodic check-ins, numeric traits/bond and daily trait adjustment.

## Steering and responsibility

The bundled [BEHAVIOR.md](../app/Boop/Resources/BEHAVIOR.md) defines personality.
Settings → Edit buddy behavior… creates/opens `~/.boop/BEHAVIOR.md` (or inside
BOOP_STATE_DIR) without overwriting edits. Every decision rereads it. Missing,
empty, unreadable, invalid UTF-8 or over-32-KiB overrides use the bundled guide.
Owner configuration is trusted; runtime context is data.

Rules own state, effort, celebrations, XP and attention reminders. The model
chooses dialogue/silence and supported profile memories. It has no tools or
permission authority. Approvals remain in the editor.

## What triggers a display decision

| Trigger | Response | Default timing |
| --- | --- | --- |
| First work signal for a distinct turn | Short task-aware acknowledgement; small nod | 1.5 seconds, once per turn |
| Started turn completes | Proportional completion moment | Three duration tiers; no second post-celebration remark |
| Active turn crosses 5 or 15 minutes | Optional patient/exasperated remark and weary face | 4 seconds; desk-wide 2-minute cooldown |
| Person interacts after 18 hours away | Optional time-aware greeting and wave | 4 seconds, or merged into the same start's 1.5-second budget |
| New explicit error | Grounded error remark through existing Voice lane | Up to 4 seconds |
| Settled work-context change | Whole-desk summary on Mac only | 2-second debounce; retained until context changes |

Long-work opportunities are consumed even when attention wins, never queued.
Waiting is not a reason to pressure the person. Only a turn-start interaction or
a boop updates the persisted person-interaction timestamp; background activity
and reconnect do not manufacture a return. Local hour/time-of-day are supplied
as facts, without guessing sleep or habits.

## Shared display pipeline

`work_context_changed`, start/completed/longRunning/returned moments and explicit
errors all use the same `Voice`, guide and `BehaviorContext`.
The context contains the whole desk grouped by local repository identity,
optional event facts, previous scope and five recent actually displayed remarks.
XP, profile and coarse legacy memory are no longer engine display inputs.
Grounded payoff events and episodic callbacks are the next stages described in
[Work context](UX-WORK-SCOPE.md); they are not implemented in this first stage.

`BehaviorTasks` replaces `TransientVoiceTasks`: one outstanding display call,
latest scope and latest remark, with remarks ahead of scope. Scope updates
coalesce for two seconds; moment and error opportunities remain immediate.
Runtime changes, stop, cards and context revisions invalidate stale
replies. There is no per-task model, semantic classifier or periodic narration.

Working/thinking/waiting sessions participate, plus idle/error sessions active
within 15 minutes. End/stale cleanup removes sessions immediately. All eligible sessions
are considered; the Mac lists every session and only the device preview is bounded. Worktrees share the
canonical Git common-directory identity; same-name unrelated roots stay separate.

First/latest user intent excerpts (768 UTF-8 bytes each) stay in engine memory
only and are removed on scope expiry, session end, stop or retirement. This is
an intentional exception to the former no-prompt model boundary: knowing what
we're making requires intent. No tool arguments/output or transcripts are added.
The desk budget is 6 KiB of encoded JSON, reserving room below the 8 KiB context
target for event and presentation fields. Excerpts share allowance across
projects and their tasks. If metadata cannot fit, report partial coverage and
omitted counts rather than silently selecting a project. Unknown intent stays
unknown. Model factuality and private-text disclosure require live evaluation.

Scope is text or SILENT, at most 120 UTF-8 bytes, retained on Mac until context
changes. It no longer causes device pop-ups. Invalid scope is rejected whole.
Moment text is printable ASCII: 24 characters/bytes and one line for starts,
returns and long work; 48/two lines for completion. Host and firmware enforce
408 px width with 24 px captions or 32 px full-celebration text; overflow is
silent, never shrunk or clipped. Tiny completions request no text. The shared
runtime result stays text-or-SILENT; supported expressions come from guide policy.

Moment replies must match both event ID and completion count and arrive before
the existing deadline. A reply cannot extend, replay or resurrect a moment.
Explicit-error bubbles retain their 63-byte/four-second limit. Last five accepted
remarks stay in memory; no durable dialogue history is added.

## Declarative policy in the same guide

One fenced `boop-policy` JSON object controls thresholds, dwell times, cooldowns,
expression selection and optional short fallbacks. See the complete schema and
bounds in [Turn moments](UX-TURN-MOMENTS.md#guide-policy).
Missing top-level fields inherit bundled values. Invalid types/values or unknown
keys fall back atomically to bundled policy while owner prose remains untouched.
The engine rereads policy on events; wording reads the same guide for each call.
A policy change affects the next opportunity, not an already-issued deadline.

Fallbacks are optional immediate guide-authored text, validated for the occasion.
An unavailable or late model leaves that fallback/animation until normal expiry;
a timely model SILENT clears the phrase; invalid runtime generation retains the
fallback, and extra renderer-fit validation can clear unsafe text. This keeps a 1.5-second start
responsive even when generation takes longer. No hardcoded renderer phrase list.

## Readiness refinement

Keep the existing one-call display lane, full owner guide and five-second
deadline. Scope requests with no supplied intent stay silent without calling the
model. A guided-generation candidate with per-task purposes and an explicit
silence flag lives only in the opt-in test replay. Expanded live trials still
missed purposes, retained canceled work and invented success; it is not enabled
in the app. Schema compliance does not establish semantic confidence.

Reject exact repeated remarks, private-looking output (paths, email addresses,
credential assignments), and output echoing explicit credential values from the
input. Mask recognizable private values in display input before generation.
These checks are limited protection, not proof that arbitrary prose contains no
private information. Byte overflow and invalid model results are discarded;
errors and scope stay silent, while a turn moment keeps its validated guide fallback.
The live semantic-quality gate stays open until expanded replays pass.

## Runtime

Apple Foundation Models on supported macOS 26+ runs locally, with fresh sessions,
temperature 0.4 and a five-second async deadline. No cloud fallback or bundled
alternate model. The single display lane and existing profile lane keep reflection independent.
Every display trigger is an opportunity, not an obligation to speak. Prefer
SILENT for thin evidence, uncertain interpretation, redundant remarks or occasions
already served by the face/animation. A useful greeting may still be appropriate;
novel factual content is not required for every social moment. Confidence means
support in the supplied context, not an uncalibrated numeric self-rating.
Moment fallback behavior is described above; errors and Mac summaries have no
stock fallback. Reflection failure leaves the profile unchanged.

## Private memory learning

Once per day after twenty inactive minutes on AC power, reflect on evidence up
to the previous day. Reduced facts expire after 30 days. The model receives at
most 100 facts and twenty existing profile lines, with no approval decisions or
raw identifiers. Return SILENT or `{"memories":[{"line":"…","evidence":[0]}]}`.

At most five new memories per update, each at most 240 UTF-8 bytes and citing
valid supplied evidence IDs. Invalid memory output rejects the update; successful
reflection is idempotent per local day. Old trait fields are ignored, never
applied. No numeric energy, cheek, warmth, curiosity or bond updates remain.
Legacy values stay stored but inactive. The guide selects useful supported
preferences rather than daily recaps. Profile lines remain inspectable/deletable.

Foundation Models receives the guide in its instruction field and the compact
JSON snapshot as input. This separates owner instructions from runtime data;
it does not prove model adherence. The current real-model evaluation failed
semantic coverage expectations. See the [evidence](evidence/work-context-2026-09-11/README.md).
Sessions with no known workspace share an explicitly unknown project bucket;
this does not claim they belong to one real project. Owner guide overrides are
preserved, so an old override may need a work-context section added by its owner.
