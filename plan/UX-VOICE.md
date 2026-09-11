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

## Shared display pipeline

`work_context_changed`, return greetings, explicit errors and the existing
post-celebration remark all use the same `Voice`, guide and `BehaviorContext`.
The context contains the whole desk grouped by local repository identity,
optional event facts, previous scope and five recent actually displayed remarks.
XP, profile and coarse legacy memory are no longer engine display inputs.
Grounded payoff events and episodic callbacks are the next stages described in
[Work context](UX-WORK-SCOPE.md); they are not implemented in this first stage.

`BehaviorTasks` replaces `TransientVoiceTasks`: one outstanding display call,
latest scope and latest remark, with remarks ahead of scope. Scope updates
coalesce for two seconds; existing remark opportunities remain immediate.
Runtime changes, stop, cards and context revisions invalidate stale
replies. There is no per-task model, semantic classifier or periodic narration.

Working/thinking/waiting sessions participate, plus idle/error sessions active
within 15 minutes. End/stale cleanup removes sessions immediately. All sessions
are considered, independent of the six-row popover preview. Worktrees share the
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

Scope is text or SILENT, at most 120 UTF-8 bytes; reject overflow rather than
clipping away another project. It persists on calm Mac/device views until its
context changes, with no sound, animation, XP or four-second expiry. Invalidate
old scope immediately, include it as comparison data, and accept identical text
without dialogue-repeat filtering or durable history. SILENT clears scope.

Temporary bubbles remain four seconds and at most 63 UTF-8 bytes. They cannot
cover attention or wake Buddy. Existing duration celebrations and their
post-idle opportunity are unchanged. Scope has no durable history; actual
remarks retain only the last five in memory for this display path.

## Runtime

Apple Foundation Models on supported macOS 26+ runs locally, with fresh sessions,
temperature 0.4 and a five-second async deadline. No cloud fallback or bundled
alternate model. The single display lane and existing profile lane keep reflection independent.
Unavailable/invalid responses produce one neutral greeting/error line when not
already used, otherwise silence. Reflection failure leaves the profile unchanged.

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
