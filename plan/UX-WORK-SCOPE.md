# Proposal: a companion that follows the work

Companion summaries and remarks are English-only in the first version. Context
uses `language: "en"`; changing the app UI language does not cancel, clear or
regenerate companion text. Private legacy reflection retains its language setting.

Status: stage 1 development implementation; automated and USB verification passed. Live-model semantic quality is not yet a pass. Richer result events and episodic callbacks remain planned. Owner direction, 2026-09-11: Boop should
know what we're working on, recognize the payoff, and remember a little of our
history. The first implementation starts with knowing the whole desk. Keep the
mechanism simple and reusable; personality and behavioral judgment live in Markdown.

The proposed model-facing guide is [draft BEHAVIOR.md](drafts/BEHAVIOR.md).
The shipped `app/Boop/Resources/BEHAVIOR.md` now includes this guide plus compatibility
instructions for existing temporary and private-reflection occasions. Owner
overrides are preserved, never overwritten.

## 1. One guide, one call shape

Relevant event → context snapshot + BEHAVIOR.md → local model → text or SILENT.

All three experiences use the existing Voice service and local runtime. No
per-task model, project-summary model, callback detector, topic taxonomy or
planner. The model reads the whole desk and does the semantic grouping in one
call. A callback is wording informed by an earlier observation, not a separate
feature that invokes another model.

The guide defines voice, grouping, abstraction, restraint, reactions and memory
use. Code supplies facts and controls delivery. Editing Markdown can change how
Boop behaves at existing occasions; adding a new event source or physical
interaction still requires code. A Markdown file cannot make absent data exist.

| Occasion supplied by code | Model's job, defined in the guide | Destination |
| --- | --- | --- |
| `work_context_changed` | Describe the whole desk, optionally with a relevant callback | Persistent scope phrase |
| `result_observed` | Acknowledge a supported result, optionally remembering a related result | Temporary remark |
| `returned` | Greet naturally; refer to work only when current context supports it | Temporary remark |

Every call returns plain text or exactly `SILENT`. No structured action plan or
model-selected animation. The host already knows the destination from the occasion.
An identical scope phrase stays unchanged; SILENT clears scope text for that
revision. SILENT for a remark means nothing is shown. This distinction avoids
keeping an inaccurate old summary after the desk changes.

## 2. Input before this implementation

Before stage 1, `VoicePrompt.make` supplied these fields, when available:

| Current input | Actual content / limitation |
| --- | --- |
| Occasion | Greeting, explicit error, after-celebration completion; other legacy/internal cases exist |
| State | Creature state, effort, session count, last completed duration |
| Agent | One known agent name, not every task's context |
| Time/language | Time-of-day bucket; companion language fixed to English |
| Progress | XP, current/best streak, active days, completed turns, today's XP |
| Profile | Up to three learned profile lines |
| Memory | Up to five reduced outcomes such as `test_pass` or `completed_turn_180s`, with dates |
| Recent lines | Up to twenty exclusions from the stored set; not reliable chronological display history |
| Output budget | UTF-8 byte limit |

It does **not** give the model a list of projects, individual task intentions,
specific check identities, or grounded shared episodes. Consequently, it cannot
currently produce the proposed experience just by changing its guide.

The hook boundary already accepts bounded user prompts for supported turn-start
events. The extractor reduces these to coarse topic/tone facts. Hook availability
is harness-dependent and still needs live verification. We should use those
existing inputs before considering new integrations; missing intent stays unknown.

## 3. Proposed common context

A single snapshot with a few optional fields serves all occasions. Omit XP,
streaks and numeric personality inputs: none is necessary for these experiences.
The following is a **synthetic target input**, not data collected from a live desk:

```json
{
  "occasion": "work_context_changed",
  "language": "en",
  "max_utf8_bytes": 120,
  "desk": {
    "coverage": "complete",
    "projects": [
      {
        "id": "p1",
        "name": "Boop",
        "tasks": [
          {"id": "t1", "state": "working", "intent": "Improve the device layout"},
          {"id": "t2", "state": "working", "intent": "Make the greeting animation smoother"},
          {"id": "t3", "state": "working", "intent": "Simplify the Mac settings screen"},
          {"id": "t4", "state": "waiting", "intent": "Clarify the connection status UI"},
          {"id": "t5", "state": "idle", "intent": "Polish setup instructions"}
        ]
      },
      {
        "id": "p2",
        "name": "Shop website",
        "tasks": [
          {"id": "t6", "state": "working", "intent": "Update homepage copy and layout"}
        ]
      }
    ]
  },
  "event": null,
  "memories": [],
  "previous_scope": "Polishing Boop's app and device.",
  "recent_remarks": []
}
```

Candidate output: `Boop polish and shop website updates.`
With only p1 present: `Polishing Boop's app and device.` These illustrate the
same call adapting to scope; they are not required exact strings in tests.

### Field meanings and sources

| Field | Source and meaning |
| --- | --- |
| `occasion` | App event; chooses an existing section of the guide |
| `desk.projects` | All eligible sessions grouped by project; not the six-row UI preview |
| Project ID/name | Opaque local identity and readable label; never an absolute path or remote URL |
| Task ID/state | Existing session identity and lifecycle, normalized to working/waiting/idle/error |
| `intent` | Bounded user-provided task text, not an LLM-generated per-task summary; null when unknown |
| Optional `latest_request` | Latest user instruction when it differs from the initial intent; helps interpret “continue” and later scope changes |
| `coverage` | `complete` means all eligible tasks are represented, not that all their intent is known; `partial` means input bounds or source limitations omitted scope |
| `event` | What prompted this call, including supported evidence when it is a result; return events include `new_intent_since_return` so surviving old sessions are distinguishable from newly requested work |
| `memories` | A few local observations from the same projects; not model-written personal traits |
| `previous_scope` | Last accepted phrase for comparison; not proof it remains correct |
| `recent_remarks` | Last five actually displayed remarks, in chronological order, to discourage repetition |

Worktrees use their canonical Git common directory as the same project identity.
Unrelated repositories with identical folder names remain separate. Non-Git
workspaces use canonical directory identity. Identity resolution is adapter work,
not something the model guesses from similar names. Model-facing IDs are opaque.

Include working/thinking/waiting tasks and idle/error tasks active within the
last 15 minutes. Remove ended sessions immediately. The grace period keeps
multitasking visible across short pauses; idle presence does not mean unfinished
work. This is an initial tuning value. Do not treat a long-running tool's silence
as inactivity or infer that the owner resumed work merely from reconnecting.

Use the first known user intent plus an optional latest request to ground short
follow-ups. On a changed request, the latest request takes precedence; the model
may decide that it replaces the earlier intent. Avoid a separate topic-change
classifier. Original context is bounded and may become insufficient; allow silence.

## 4. Payoff uses the same snapshot plus an event

On a result call, set `occasion` to `result_observed`, use the remark byte limit,
include the current desk, and supply an event such as:

```json
{
  "kind": "check_result",
  "project_id": "p1",
  "task_id": "t1",
  "subject": "reconnect test",
  "check_id": "check7",
  "outcome": "pass",
  "evidence": "observed_tool_result",
  "observed_at": "2026-09-11T09:20:00+09:00"
}
```

Candidate output: `Reconnect test passed!`
If a supplied observation shows **the same check** previously failing, a possible
output is `There we go!` A routine repeat pass can produce `SILENT`.

`subject` is optional and must come from a supported, safely displayable check
label. Task intent “fix reconnect” plus exit code zero from an arbitrary shell
command does not establish that reconnect passed. `check_id` identifies a matched
check invocation target, not merely the runner name “test.” If the adapter can
only establish that a test command passed, expose that weaker fact with no
specific subject. Omit uncertain identity; do not manufacture cross-run matching.

Existing call/result matching and runner parsing provide a starting point, but
specific subjects and stable check identities are **new adapter work**, not
already available facts. An agent's closing claim, if ever supplied, must use
`evidence: agent_report` and cannot masquerade as observation.

A plain turn end is represented as `kind: turn_ended` with no success outcome.
The guide usually chooses silence. The call does not promote an idle session to
“verified success.” A recognized check result does not change the app's state or
celebration size; coordinating richer physical payoff remains later UX work.

## 5. Familiarity is a few observations in that same input

A result can become a small local observation without a second model call:

```json
{
  "project_id": "p1",
  "task_id": "t1",
  "kind": "check_result",
  "subject": "reconnect test",
  "check_id": "check7",
  "outcome": "pass",
  "evidence": "observed_tool_result",
  "observed_at": "2026-09-10T17:40:00+09:00"
}
```

For a later pass of check7 in p1, supply this in `memories` alongside the current
result. `Still behaving.` is a possible callback; it is not a required response.
For a new task about reconnect, the same observation can inform a scope phrase
such as `Back to reconnect work.` It must not erase other projects from the summary.

For `returned`, supply an event such as `{"kind":"returned","away_seconds":86400,"new_intent_since_return":false}`.
Use only a measured time-away value. A greeting can be ordinary even when there
are memories. Old sessions surviving overnight are not evidence of a fresh intent;
only a new request establishes what the owner is returning to work on.

**Smallest memory implementation:** reuse the existing fact store. Retain at
most twenty recent eligible observations per project within its existing 30-day
fact retention; provide at most five observations across represented projects in
a call, preferring the event's project for a result and otherwise distributing
across projects. Deduplicate repeated deliveries of the same event. Store only
bounded, safe labels and structured evidence; never raw prompts, tool output,
commands, file contents or approvals. Clear/delete remains available to the owner.

No daily reflection, embedding index, personality drift or separate memory-writing
model is needed for these callbacks. This does not require deleting the current
profile/reflection system in the first change; the prototype simply does not need
it. A later choice to consolidate or remove that system should be explicit.

If semantic task labels become necessary for more expressive memories, design
that separately after testing these factual callbacks. Do not quietly persist
raw intent excerpts or promote a generated phrase into verified history.

## 6. When the app calls and what it shows

Keep scheduling generic: relevant events request a decision, and the existing
Voice service handles it. Start with a two-second debounce and one outstanding
call. While it runs, retain one latest pending snapshot instead of building a
queue. A fresh result or return takes precedence over a scope-only update;
scope refresh follows if still needed. Replaced remarks are simply not spoken.

The three sources are changed intent/session membership (including idle expiry),
matched check results/turn endings, and the existing return-greeting event.
Unchanged tool activity and periodic timer ticks do not independently call the
model. Do not add separate cadence engines for the three behaviors. If real use
shows excessive generation, add one shared throttle rather than per-feature rules.

A pending result has a ten-second freshness limit; a late result is discarded.
This is a delivery guard, not a model decision about how excited Boop should be.
There is no need to narrate every result, and recording an observation does not
require displaying a remark.

On any material scope change, invalidate the old scope phrase. Pass it to the
next request as comparison data, but don't display stale claims while waiting.
Validate a reply against its input revision and current delivery
eligibility. Identical accepted text should not restart an animation. Keep the
existing five-second asynchronous model deadline and local-only runtime fallback.
Unavailable, invalid or timed-out output means no contextual phrase, not invented
fallback detail. Existing factual status and physical interactions keep working.

The scope phrase persists beside the buddy and in Mac Overview. Temporary
payoff/greeting remarks last four seconds. Cards/errors/system UI take priority.
Scope survives a temporary cover if its context revision remains current.
No new sound, gesture or animation is required for scope. The current firmware
suppresses dialogue while the dashboard is active, so showing persistent scope
alongside counts needs an explicit presentation and wire change when implemented.

## 7. Bounds, privacy and validation

Proposed initial output limits: 120 UTF-8 bytes for scope, 63 for a temporary
remark. The longer scope budget permits a compact multi-project phrase;
120 bytes is a ceiling, not an invitation to fill the screen. Reject oversized
scope output rather than truncating away the second project. The existing filter
currently truncates, so this requires an explicit validation change.

Target at most 8 KiB of encoded context, excluding the guide, with at most
768 bytes each for initial intent and latest request. Reduce excerpt lengths
fairly across projects before omitting tasks. If complete representation will
not fit, set `coverage: partial`, include omitted project/task counts, and let the
guide choose an honest broad description or silence. Never take the newest six
sessions and imply they are the whole desk. Actual local-model context capacity
must be measured; these are input engineering targets, not a verified runtime fit.

Prompt excerpts are in-memory input only, removed on session end or scope expiry.
No raw prompt logging, persistence or cloud fallback. This explicitly changes
the current blanket prohibition on prompts in model context. Treat runtime data
as untrusted; use it only to understand work. Safe-label filtering and output
bounds cannot prove factuality or eliminate all private-text disclosure: evaluate
both in live-model tests before enabling the feature for ordinary use.

For memory context, source IDs establish provenance, not semantic truth. Test
that unrelated failures/passes cannot become a fabricated “we fixed it” story.

## 8. Implementation order and review cases

1. Add whole-desk intent context and `work_context_changed` to the existing Voice
   path; show a persistent scope phrase. No memory changes are required yet.
2. Supply supported result events to the same path; add the payoff section of
   the guide and the temporary delivery rules.
3. Supply a few persisted observations to those same calls and returns; enable
   the guide's restrained callbacks. No additional model pipeline.

| Replay | What we want to learn |
| --- | --- |
| Five tasks, one project | One meaningful umbrella, not five status reports |
| Different purposes in one repository | Both purposes survive grouping |
| Five tasks in A, one in B | B is still represented |
| Three or more projects | More abstraction without a false common goal |
| Worktrees and same-name unrelated folders | Correct identity independent of display name |
| More than six sessions, null intent, oversized input | Honest coverage and no invented detail |
| Short follow-up and an explicit task replacement | Context continuity without clinging to old work |
| Turn end, test pass, unrelated earlier failure | Earned reaction, no inflated success claim |
| Same check failing then passing | Opportunity for a specific payoff |
| Same project, unrelated old observation | No forced callback |
| Return without a new request | Greeting without claiming resumed work |
| Task switch during generation, shutdown | No stale delivery |
| Unavailable/slow model, priority card | Factual status and attention remain usable |
| English companion text with either UI language | Brief, legible phrases; UI language changes preserve scope |

Automated tests establish context coverage, provenance, bounds and lifecycle.
Real-model replays establish semantic quality; actual display/BLE checks establish
presentation. Stage 1 changes the shared display path, scope presentation and additive wire
field. Live model, editor and hardware verification are tracked in PLAN.md.

## Stage 1 implementation notes

The first stage uses `work_context_changed` plus existing `greet`, `completed`
and `uhoh_error` occasions through the same snapshot and Voice instance. It does
not add check-result triggers or persist episodes yet (`memories` is empty).
Existing remarks remain immediate; only scope coalesces for two seconds.
Work-context revisions also invalidate pending remarks. The 6 KiB desk budget
leaves headroom under the proposed 8 KiB common-context target. Actual result
freshness and durable observations belong to stages 2/3, not this rollout.

[Stage 1 evidence](evidence/work-context-2026-09-11/README.md): 360 app tests,
18 USB checks, 49 independently reproduced goldens. Foundation Models samples
remain unreliable for whole-desk coverage; this is an open product
quality gate, not a successful model demonstration.
