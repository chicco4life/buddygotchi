# Component behaviors

Reviewed against this checkout: 2026-09-11. This is the compact product reference
for discussion and tuning; detailed visual and wire contracts remain linked
below. **Current** means found in source, not independently verified on a running
device. **Target** marks intent that is not fully implemented; **gap** marks a
disagreement or limit. Owner simplifications through 2026-09-11 are implemented in this checkout; see PLAN.md for validation.

Jump to: [States](#2-states-and-attention) · [Effort and celebrations](#3-effort-and-celebrations) · [XP](#4-xp-turns-and-streaks) · [Local LLM](#5-local-llm-and-dialogue) · [Memory](#6-personality-and-memory) · [Attention](#7-native-approvals-and-attention-reminders) · [Device/app](#8-device-mac-app-and-sound) · [Sharing](#9-sharing-and-rankings) · [Review queue](#review-queue)

## 1. Who decides what

| Component | Responsibility | Does it use the local model? |
| --- | --- | --- |
| Hooks and server | Receive agent activity and passive attention | No |
| Extractor | Recognize runners, outcomes and topics | No; deterministic readers |
| Core | Choose state, priority, celebrations, reminders and award events | No; rules and timers |
| Growth and memory | Persist XP, streaks, facts, legacy traits and profile | Accounting/storage rules; Markdown + model choose learned memories |
| Behavior controller | Interpret stats/memory through Markdown; choose dialogue or silence | Local model; minimal fallback |
| Outputs | Mac status UI; hardware face, motion, buttons and sound | No; render the host state |

The local LLM directs dialogue, personality and memory selection
using the guide and structured inputs. Rules retain outcomes, XP accounting, base states and
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
| Needs you | A passive attention request exists; clear, resolve, abandon or expire it to leave | Wide eyes, amber field, compact request footer |
| Done | A started turn of at least one minute completes; visible only while no request or uh-oh wins | Hop, cheer or dance, then return to remaining session state |
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

## 3. Effort and desktop celebrations

The device completion notice below has its own five/eight-second presentation.
These duration rules govern the desktop celebration.

One task means one started work period ending in a completed turn. Time runs
from its first work signal, including waits; each new period starts fresh.

| Task length | Effort | Celebration | Host duration |
| --- | --- | --- | ---: |
| Under 1 minute | Light | None | — |
| 1 to under 3 minutes | Light | Hop | 1.5 s |
| 3 to under 5 minutes | Hard | Cheer | 2.5 s |
| 5 minutes or longer | Grinding | Dance | 4 s |

Sub-minute completions still earn XP and record their outcome; they make no
completion sound. They do not
start or interrupt a celebration. Working starts light, becomes hard at three
minutes and grinding at five minutes.

Errors, retries, first completions and remembered history do not resize the
celebration. Completions within 3 seconds fold together: a smaller or equal
one does not restart the larger animation; a larger one replaces it. Higher
priority states can hide it while its timer expires. No delayed replay.

Named moment detectors and milestone creation are removed. Recent completed
turn durations, tool outcomes and errors are factual model inputs. Historical
moment records remain readable. No completion stories, gifts or collection.

**Tune:** duration tiers, animation lengths, folding. Sources:
[reducer](../app/Boop/Core/BuddyReducer.swift), [extractor](../app/Boop/Core/Extractor/Extractor.swift).

## 4. XP, turns and streaks

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

XP accumulates without levels or a product cap. The Mac shows cumulative XP,
completed turns, current streak and a twelve-week daily turn-count grid.
Darker squares indicate more completions; hover gives an exact count.

Streaks count consecutive active local days. Today is not missed until
tomorrow; a missed day breaks the current streak. No rest credits, earning or
spending. Best streak and XP remain. Historical keepsakes remain stored;
new milestone keepsakes are not generated.

**Tune:** the two award weights and level curve. Details:
[XP](XP-AND-SKILL-TREE.md), [growth](UX-GROWTH.md).

## 5. Local LLM and dialogue

BEHAVIOR.md defines personality directly. Settings → Edit buddy behavior… opens
`~/.boop/BEHAVIOR.md`; changes apply on the next decision. The local model
chooses a short line or SILENT on return greetings, explicit errors, and after
a celebration returns to idle. Five-minute check-ins are removed.

Context is current state/work, language/time, agent, growth, a few recent factual
outcomes, up to three learned profile lines and twenty prior lines. No numeric
personality traits, familiarity counters, usual-hour inference, old moments,
raw transcript or tool arguments. Growth remains descriptive context.

Apple Foundation Models runs locally when available, with a five-second async
deadline. New state/cards invalidate pending replies. Bubbles last four seconds,
are capped at 63 UTF-8 bytes, never cover attention cards and never wake Buddy.
Unavailable models use a neutral greeting/error fallback, otherwise silence.
The model cannot change states, XP, celebrations or permissions. See [Voice](UX-VOICE.md).


## 6. Personality and memory

Owner simplification: personality lives directly in BEHAVIOR.md. Familiarity
comes from supported memories, not numeric traits or bond adjustments.

Keep three inputs: the editable guide, a small inspectable/deletable learned
profile, and bounded recent factual outcomes and dialogue. Retire numeric energy,
cheek, warmth, curiosity and bond, usual-hour detection, known-project and
lifetime-session counts, and historical moments from model context. Legacy
stored values remain inactive; growth and time-away greetings are unchanged.

Reduced facts last 30 days. Once daily after 20 minutes inactive on AC power,
the local model may select up to five evidence-backed profile lines from at
most 100 facts. Profile context is bounded to 20 lines for reflection and three
for dialogue. The model may stay silent. Invalid/unavailable output leaves the
profile unchanged. No trait updates, XP changes or approval evidence.


## 7. Native approvals and attention reminders

Approvals belong entirely to the editor/agent. Buddy interception, opt-ins,
stakes classification, approve/deny controls, decision holds and acknowledgement
handling are retired. Old approval endpoints return passthrough immediately,
even with stale enabled settings. Passthrough is not permission granted by Boop.
New hook installations do not register permission interception.

Buddy shows only reliably reported passive attention requests. Activity and
execution gates are not evidence of human waiting. Requests show oldest first,
with queue count and supplied reason or tool name; no safety classification or
decision controls. Native Codex approval waiting cannot reliably be mirrored.

The existing reminder ladder stays: arrival rung 0, 60 seconds rung 1,
120 seconds rung 2, with no repeating final rung. Dismissal snoozes only that
request until cleared; the next request starts fresh. Quiet mode mutes all
sounds while visual escalation continues. Snoozing never resolves a request.
Passive requests retain the 290-second lifetime. Hooks fail open if Boop is down.


## 8. Device, Mac app and sound

| Surface | Expected behavior |
| --- | --- |
| Device | Physical companion; six states, compact passive attention footer; no rendered session dots |
| Buttons | Context first: attention dismissal, then bubble dismissal/stats/affection as applicable. Wake press is consumed. Former Focus hold toggles Quiet mode; legacy quick-command gesture has no host action. |
| Motion | Shake wobble and face-down nap suppressed during prompts; boop has one heart per interaction |
| Display priority | System card → request → uh-oh bubble → stats → bubble → overlay → face |
| Dim target | 210/255 awake, 255 with card, 90 after 2 min inactivity 28 asleep; pending request never dims; automatic idle sleep never turns display fully off |
| Sound | Short authored interaction/completion motifs plus a nudge motif; Quiet mode mutes all, normal volume fixed at step 1; current Waveshare board has no speaker |
| Mac | Static menu icon; 360 pt transient popover opened by the person; state transitions never open it; no ordinary desktop pet face |
| Overview | Status, attention cards, XP and all sessions inline; grows through 10 rows within screen bounds, then scrolls |
| Mac overview/settings | Sessions follow status; device then compact XP with tasks and streak. No Activity pane. Attention cards never cover Settings; return to Overview to snooze. Settings is one scrollable form. |
| Connection/update | Show real link/battery state; unknown battery omitted. Firmware check failure is “Check unavailable”, distinct from installation failure. |

Pixel positions, posture thresholds, shutdown stages, sound motifs and motion
timelines belong in [device UX](UX-DEVICE.md), [Mac UX](UX-APP.md), and
[wire contract](WIRE-V2.md). Dim values above are the visual spec, not a new
hardware verification claim. USB-only debug checks do not close production BLE
gates; webcam verification is explicit session opt-in only.

## 9. Sharing and rankings

Share-card export and its authored captions are removed for now. Leaderboards, enrollment, friends,
network synchronization, rank UI and device signing are removed and recorded
as optional enhancements in [IDEAS.md](IDEAS.md). BLE bonding and firmware OTA
remain independent of this removal.

## Review queue

The accepted simplifications above are implemented in this checkout. Next tune
the Markdown behavior guide against ordinary use: relevance, silence, factuality
and localization. Delivery and physical-device verification gates remain in
[PLAN.md](PLAN.md) and [VERIFICATION.md](VERIFICATION.md).

## Glanceable activity and completion notices (2026-09-11)

This replaces the persistent mixed-session dashboard. Any working session keeps
the full working face with a small working count; otherwise the buddy is idle.
A successful completed turn (including short turns) gets a five-second notice,
agent label, large thread title and a sage-green wash (250 ms in, 600 ms out).
Concurrent completions update one notice without restarting the cheer or wash:
latest two titles, total completion count, at least two seconds for arrivals
where possible, hard eight-second cap from the first arrival. Three-second
cooldown updates history only. Explicit attention/errors take priority and
cancel the current notice; it does not replay after dismissal or reconnect.

Tap the face to inspect threads when working, or when a last completion exists.
A normal tap anywhere on the table returns immediately to the buddy, including
when there are multiple thread/history pages. The bottom-right Next control
alone advances pages (wrapping to the first); Back is always visible at bottom
left. Either physical short-tap button also exits. Navigation takes priority over
hidden dialogue so a bubble cannot consume an exit tap. The left-aligned table
has 40 px side margins, 24 px at the top and bottom, and three inset rows. Idle with no completion retains tap affection; primary hold always
retains affection. Table rows update without completion interruptions. A quiet
Last finished footer opens recent history through the same paged detail view.
History has six entries; the device receives up to twelve session rows, ordered
by stable session ID. Totals and an explicit omitted-row count expose the
bounded preview. Older idle chats imply no obligation or unread state.

Use explicit hook thread/session titles when supplied. At Codex session/turn
boundaries, read matching title metadata from at most the last 256 KiB of its
local session index, off the main actor. Otherwise use project plus short stable
session ID. Never read transcripts for titles. Do not display raw prompt or command text as a title.
Names are ephemeral display metadata, never model memory. UTF-8 titles are
bounded to 47 bytes; omit older history and preview rows as needed to satisfy
the 1536-byte frame cap, retaining the full session count.
Session removal, stale cleanup, failures and duplicate end events never cheer.
