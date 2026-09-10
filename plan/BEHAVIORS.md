# Component behaviors

Reviewed against this checkout: 2026-09-11. This is the compact product reference
for discussion and tuning; detailed visual and wire contracts remain linked
below. **Current** means found in source, not independently verified on a running
device. **Target** marks intent that is not fully implemented; **gap** marks a
disagreement or limit. Owner simplifications through 2026-09-11 are implemented in this checkout; see PLAN.md for validation.

Jump to: [States](#2-states-and-attention) · [Effort and celebrations](#3-effort-and-celebrations) · [XP](#4-xp-levels-and-streaks) · [Local LLM](#5-local-llm-and-possible-dialogue) · [Memory](#6-bond-personality-and-memory) · [Approvals](#7-approvals-hooks-and-reminders) · [Device/app](#8-device-mac-app-and-sound) · [Sharing](#9-sharing-and-rankings) · [Review queue](#review-queue)

## 1. Who decides what

| Component | Responsibility | Does it use the local model? |
| --- | --- | --- |
| Hooks and server | Receive agent activity and authorized approval requests | No |
| Extractor | Recognize runners, outcomes, stakes and topics | No; deterministic readers |
| Core | Choose state, priority, celebrations, reminders and award events | No; rules and timers |
| Growth and memory | Persist XP, streaks, facts, traits and profile | Accounting/storage rules; Markdown + model choose learned memories and trait changes |
| Behavior controller | Interpret stats/memory through Markdown; choose dialogue or silence | Local model; minimal fallback |
| Outputs | Mac status UI; hardware face, motion, buttons and sound | No; render the host state |

The local LLM directs dialogue, personality evolution and memory selection
using the guide and structured inputs. Rules retain outcomes, permissions, XP accounting, base states and
device animations.

## 2. States and attention

One shared face summarizes all sessions. Highest priority wins:
**Needs you → Uh-oh → Done → Working → Idle → Asleep**. The oldest pending
request is shown first; a busy second agent cannot hide it. Device connection
and coding-agent activity are separate: disconnected hardware does not mean
the agent stopped.

| State | Entry and exit rules | Intended presentation |
| --- | --- | --- |
| Asleep | No sessions. Activity can wake it. | Closed eyes, slow breath, dim; no sound |
| Idle | At least one idle session; no higher-priority state | Open eyes, gentle bob/blink; occasional micro-idle |
| Working | Turn/tool activity starts or continues work; completion, waiting, error or silence can replace it | Concentration; effort adds lean, sweat or tremble |
| Needs you | An actionable approval or passive attention request exists; clear, resolve, abandon or expire it to leave | Wide eyes, amber field, compact request footer |
| Done | A real started turn completes; visible only while no request or uh-oh wins | Hop, cheer or dance, then return to remaining session state |
| Uh-oh | Explicit turn error, including agent quota errors | Slump/dim red and a generic error remark; never inferred from silence/repetition |

**Timers:** silence and repeated commands do not infer failure. An unwatched
session with no activity for more than 10 minutes is removed; process-watched
live sessions are exempt. Prompt lifetime defaults to 290 seconds. Actual
errors clear on a new turn, successful recovery or dismissal.

**Affection:** greet/boop overlays are allowed on idle, working and done only.
Sleeping gets a one-eye peek instead of hearts. Quiet mode changes
sound only, with no change to priority or reminder timing.

**Tune:** silence/stale thresholds, priority, overlay eligibility.
Sources: [reducer](../app/Boop/Core/BuddyReducer.swift),
[config](../app/Boop/Core/Config.swift), [device states](UX-DEVICE.md#8-states).

## 3. Effort and celebrations

One task means one started work period ending in a completed turn. Time runs
from its first work signal, including waits; each new period starts fresh.

| Task length | Effort | Celebration | Host duration |
| --- | --- | --- | ---: |
| Under 10 minutes | Light | Hop | 1.5 s |
| 10 to under 25 minutes | Hard | Cheer | 2.5 s |
| 25 minutes or longer | Grinding | Dance | 4 s |

Errors, retries, first completions and remembered history do not resize the
celebration. Completions within 3 seconds fold together: a smaller or equal
one does not restart the larger animation; a larger one replaces it. Higher
priority states can hide it while its timer expires. No delayed replay.

Named moment detectors and milestone creation are removed. Recent completed
turn durations, tool outcomes and errors are factual model inputs. Historical
moment records remain readable. No completion stories, gifts or collection.

**Tune:** duration tiers, animation lengths, folding. Sources:
[reducer](../app/Boop/Core/BuddyReducer.swift), [extractor](../app/Boop/Core/Extractor/Extractor.swift).

## 4. XP, levels and streaks

| Earned for | XP | Qualification |
| --- | ---: | --- |
| Completed turn | 3 | A work period had started; duplicate completion signals give nothing |
| Active day | 10 | Once per local civil day with session/work activity or a boop |

No extra awards for session starts, tokens, check-ins, retries, goal passes,
streaks or approval decisions. No hourly or daily XP rate limit. The active-day
award is a once-per-day source, not a quota on model calls.

Existing earned XP is preserved. Changing weights affects future awards;
restart and backdated additions do not reprice old history. Task count means
completed turns. XP cannot be spent and unlocks no behavior or appearance.

Level L starts at `100 × (L−1) × L / 2 + 50 × (L−1)` XP: levels 1/2/3/5/10
start at 0/150/400/1,200/4,950. There is no level cap.

Streaks count consecutive active local days. Today is not missed until
tomorrow; a missed day breaks the current streak. No rest credits, earning or
spending. Best streak and XP remain. Historical keepsakes remain stored;
new milestone keepsakes are not generated.

**Tune:** the two award weights and level curve. Details:
[XP](XP-AND-SKILL-TREE.md), [growth](UX-GROWTH.md).

## 5. Local LLM and possible dialogue

The local model decides what to say **or whether to stay quiet**, guided by one
[BEHAVIOR.md](../app/Boop/Resources/BEHAVIOR.md). Use **Settings → Edit buddy
behavior…** to edit the live override at `~/.boop/BEHAVIOR.md`; changes apply on
the next decision.

| Rules own | Markdown + model own |
| --- | --- |
| States, time-based effort, celebrations and 3 s folding, XP, approvals/nudges | Dialogue, tone, optional check-ins, memory selection and personality evolution |

**Opportunities:** return greeting, explicit error, completed turn after its celebration
returns to idle, and every
five minutes while idle/working without a prompt, bubble or overlay. An event
restarts the check interval. The model chooses a line or `SILENT`; it cannot
change states, manufacture progress or delay an animation.

**Context:** state, session count, effort, available completed-task duration,
language/time, known agent, traits, XP/progress, bounded memories, up to three
profile lines and twenty prior lines. No raw transcript or tool arguments. Private reflection separately asks the same guide/model to choose evidence-backed
memories and trait changes.

**Execution:** on-device Foundation Models when available; five-second async
deadline. A new state/card or interaction can invalidate a pending reply.
Bubbles last four seconds, never cover approvals, and never wake the buddy.
Device text ≤63 UTF-8 bytes; profile text ≤240. Style lives in Markdown;
code handles display validity, character-safe caps and exact-repeat suppression.

**Fallback:** one neutral greeting/error line, otherwise silence. Failed reflection leaves memories and traits unchanged. No greeting/error phrase banks, register
selection or lead-in percentage rules. Share-card captions remain authored.

**Tune:** edit the guide for personality, event responses and how often an
opportunity deserves speech. The five-minute scheduler and display timing remain
explicit code constants. Details: [model behavior spec](UX-VOICE.md).

## 6. Bond, personality and memory

All of these feed the same LLM behavior controller:

**Observed activity → recorded stats and memories → LLM + BEHAVIOR.md → dialogue or silence.**

| Input | Context supplied to the model | How the guide can use it |
| --- | --- | --- |
| Energy, cheek, warmth, curiosity | 0–255 traits, evolved by Markdown-guided reflection | Tone, liveliness or interest |
| Bond | 0–255 familiarity, evolved by the same guide | How familiar or affectionate the voice feels |
| XP and progress | XP, level, XP to next level, today's XP, task count, streaks, active days together | Acknowledge shared history when relevant |
| Learned profile | Up to three inspectable/clearable profile lines | Relevant preferences and habits |
| Recent history | Up to five recent factual outcomes/durations and dates; legacy moments remain readable | A small callback when appropriate |
| Familiarity | Completed turns, lifetime sessions, known-project count; usual-hour signal once history is sufficient | Familiarity with the working rhythm |
| Recent dialogue | Up to twenty prior lines | Avoid repetition |

`BEHAVIOR.md` decides how to interpret the inputs. Low energy may suggest a
quieter line; a memory may suggest a callback. Neither requires a response.
There is no trait-to-dialogue lookup table or XP gate on conversational behavior.
The model can propose memories and trait changes during reflection; code validates
and persists them. XP, raw facts, states, celebrations and approval handling
remain deterministic. The guide steers what to remember and how personality evolves.

**Storage and reflection:** reduced facts last 30 days; XP, traits and profile
have separate persistence. Reflection runs after 20 minutes without activity,
on AC power, once for the previous day. The model receives at most 100 reduced facts and 20 profile lines, then chooses
up to five memories with evidence IDs and optional changes to energy, cheek,
warmth, curiosity and bond. Code bounds traits to 0–255 and changes to ±3 per
axis/day. There are no fixed habit detectors or automatic bond awards. Normal behavior requests get the bounded summary,
not the whole database. Raw paths, transcripts, approval decisions and archived
agent drawings are excluded. Historical denied-approval facts remain readable
but no longer affect trait drift; new decisions do not produce memory facts.

**Tune:** edit the guide to change what the inputs mean for behavior. Change
[UX-GROWTH.md](UX-GROWTH.md) and the accounting code only to change how the
XP is earned or storage limits change. [Runtime details](UX-VOICE.md).

## 7. Approvals, hooks and reminders

**Approve in the editor/agent by default.** Buddy interception is explicit opt-in,
not a parallel approval surface: some integrations replace the native dialog
while Buddy holds the request. Server-side checks enforce opt-in even for stale
hooks. Turning it off releases held requests to the native flow.

Activity is not evidence that a human must approve. Claude tool-use hooks
report activity; its permission boundary can be intercepted when enabled.
Codex stays with native approval by default: both global approval mode and
the separate Codex switch are required to intercept. With that switch off,
Boop cannot reliably mirror native approval waiting. Cursor execution gates
report activity, not authoritative human-waiting status. Hooks fail open if
Boop is unavailable; passthrough is not permission granted by Boop.

Stakes are deterministic: read-only is **fine**, recognized dangerous patterns
are **careful**, other tools are **check it**. The actual command drives safety
classification; the agent-provided reason is displayed when present, otherwise the tool name.
Generated explanatory gloss templates are removed.
Pattern matching is not a comprehensive shell safety analyzer.

| Interaction | Current contract |
| --- | --- |
| Multiple requests | Oldest first, with queue count; passive requests have no approval buttons |
| Device arming | Card visible ≥600 ms before a decision is accepted |
| Approve | Tap primary for ordinary stakes; hold 2 s for careful |
| Deny | Hold secondary 1 s for actionable approval |
| Feedback | Sending until host acknowledgement; “no link?” after 3 s without confirmation |
| Competing surfaces | First valid decision from Mac/device wins; stale IDs cannot decide a newer request |
| Timeout | Host defaults 290 s, below hook curl 300 s and registered hook timeout 310 s |
| Nudge ladder | Arrival rung 0; at 60 s rung 1; at 120 s rung 2, for every stakes level |
| Dismiss reminder | Reset rung and snooze this request until cleared; the next request starts fresh |

Quiet mode silences every sound, including careful requests; visual escalation
continues. Snoozing is not resolving/approving the request.

**Tune:** approval ownership, timeout versus reminders, dismissal behavior.
Details: [help](UX-HELP.md), [hook audit](HOOK-REVIEW.md),
[stakes policy](../app/Boop/Core/CardStakes.swift), [wire](WIRE-V2.md).

## 8. Device, Mac app and sound

| Surface | Expected behavior |
| --- | --- |
| Device | Physical companion; six states, compact approval footer and persistent action labels; no rendered session dots |
| Buttons | Context first: prompt decision, then bubble dismissal/stats/affection as applicable. Wake press is consumed. Former Focus hold toggles Quiet mode; legacy quick-command gesture has no host action. |
| Motion | Shake wobble and face-down nap suppressed during prompts; boop has one heart per interaction |
| Display priority | System card → request → decision feedback → uh-oh bubble → stats → bubble → overlay → face |
| Dim target | 210/255 awake, 255 with card, 90 after 2 min inactivity 28 asleep; pending request never dims; automatic idle sleep never turns display fully off |
| Sound | Short authored interaction/completion motifs plus a nudge motif; Quiet mode mutes all, normal volume fixed at step 1; current Waveshare board has no speaker |
| Mac | Static menu icon; 360 pt transient popover opened by the person; state transitions never open it; no ordinary desktop pet face |
| Overview | Status, approval cards, XP and all sessions inline; grows through 10 rows within screen bounds, then scrolls |
| Settings/Activity | Pending approvals never cover these panes; return to Overview to act. Settings is one scrollable form. |
| Connection/update | Show real link/battery state; unknown battery omitted. Firmware check failure is “Check unavailable”, distinct from installation failure. |

Pixel positions, posture thresholds, shutdown stages, sound motifs and motion
timelines belong in [device UX](UX-DEVICE.md), [Mac UX](UX-APP.md), and
[wire contract](WIRE-V2.md). Dim values above are the visual spec, not a new
hardware verification claim. USB-only debug checks do not close production BLE
gates; webcam verification is explicit session opt-in only.

## 9. Sharing and rankings

Share-card PNG export remains local and uses companion identity and progress.
It works without a device or network service. Leaderboards, enrollment, friends,
network synchronization, rank UI and device signing are removed and recorded
as optional enhancements in [IDEAS.md](IDEAS.md). BLE bonding and firmware OTA
remain independent of this removal.

## Review queue

The accepted simplifications above are implemented in this checkout. Next tune
the Markdown behavior guide against ordinary use: relevance, silence, factuality
and localization. Delivery and physical-device verification gates remain in
[PLAN.md](PLAN.md) and [VERIFICATION.md](VERIFICATION.md).
