# How Boop behaves

Current source reference, reviewed 2026-09-11. Start here for the rules shared by
both screens. [Mac app](UX-APP.md) and [ESP32 device](UX-DEVICE.md) cover their
controls and presentation. [Implementation status](PLAN.md) separates what is
implemented from what has passed live verification.

## 1. Who decides what

| Part | Responsibility |
| --- | --- |
| Agent hooks | Report session, work, completion, error and supported attention events |
| Mac core | Combine sessions; choose state, effort, celebrations, reminders and XP |
| Local model | Optionally write a scope phrase or remark; select supported private memories |
| Mac interface | Show factual status, sessions, progress, connection and settings |
| ESP32 | Render the face and text; handle touch, buttons, motion and local display timers |

Approvals stay in the editor. The model cannot approve anything or change states,
XP, reminders or animations. If Boop is unavailable, hooks let the agent continue.

## 2. States and attention

Read this table from top to bottom: the first applicable state wins across all
sessions. Device connectivity is separate from agent activity.

| State | When it applies | What the person sees |
| --- | --- | --- |
| **Needs you** | A reported passive request is pending; oldest first | Mac request details; device wide eyes and amber request footer |
| **Uh-oh** | An explicit error remains | Mac error details; device slumped face and red field |
| **Done** | A qualifying celebration timer is running | Mac completion status; device uses its separate completion notice below |
| **Working** | At least one session is working or thinking | Mac live session status; device reading gaze, with effort cues |
| **Idle** | Sessions remain, with no higher-priority state | Relaxed face, blinking and occasional small idle motions |
| **Asleep** | No sessions remain | Mac Sleeping status; device closed eyes and slow breathing |

A new turn, successful recovery or explicit error dismissal clears the relevant
error. Silence and repeated commands never imply failure or “stuck.” An unwatched
session expires after more than 10 minutes without activity; a process-watched
live session is exempt. Passive requests expire after 290 seconds by default.

Greeting and affection overlays appear on idle, working and done. A sleeping
buddy gets a one-eye peek; attention and errors take precedence over affection.

## 3. Effort and celebrations

A turn's duration runs from its first work signal through completion, including
waits. A new work period starts a new duration.

| Turn duration | Working effort | Mac core celebration | Timer |
| --- | --- | --- | --- |
| Under 1 minute | Light | None | — |
| 1 to under 3 minutes | Light | Hop | 1.5 seconds |
| 3 to under 5 minutes | Hard | Cheer | 2.5 seconds |
| 5 minutes or more | Grinding | Dance | 4 seconds |

Nearby celebrations fold within 3 seconds: a larger one replaces the current
one; an equal or smaller one does not restart it. Attention and errors can hide
a celebration while its timer runs out. Hidden celebrations are not queued for replay.

**The device has a separate completion notice.** Any completed started turn,
including one under a minute, can show a cheerful face, agent, thread title and
sage wash for 5 seconds. Other working sessions resume the working face afterward.

| Multiple completions or interruptions | Device response |
| --- | --- |
| Another completion during the notice | Update the latest two titles and total count; do not restart the motion or wash |
| Late arrival | Allow at least 2 seconds where possible, within an 8-second total cap |
| Completion during the following 3-second cooldown | Update history only |
| Attention, error or system card arrives | Cancel the notice; do not replay it afterward |
| Thread details are open | Update the rows/history without interrupting reading |
| Reconnect | Restore current state and history without replaying old completions |

Duplicate endings, session removal, stale cleanup and failures do not celebrate.
A completed turn means the agent finished its turn; it is not proof that tests
passed or the user's whole task succeeded.

## 4. XP, turns and streaks

| Event | Award |
| --- | --- |
| A started turn completes | +3 XP and one completed turn; duplicates award nothing |
| First qualifying activity on a local calendar day | +10 XP; session/work activity or a boop qualifies |

There are no other current award sources, quotas, levels, spending or unlocks.
Existing earned XP is preserved. Approval decisions never earn XP.

The Mac shows cumulative XP, completed turns, current streak and a twelve-week
daily turn grid. Hover a day for its exact count. A streak counts consecutive
active local dates; today is allowed to remain incomplete until tomorrow.
A missed day breaks the current streak, preserving best streak and XP.
See [Growth](UX-GROWTH.md) for grid details and [Accounting](XP-AND-SKILL-TREE.md).

## 5. Local LLM and dialogue

Every trigger offers a chance to speak, **not a requirement**. Thin evidence,
uncertain meaning, repetition or a moment already served by the animation should
produce silence. A simple greeting can still be worthwhile.

| Trigger in the current app | What may appear | Timing |
| --- | --- | --- |
| Eligible projects, sessions, status or first/latest request changes | A phrase describing the whole desk | Wait for 2 seconds of settled context; persist until context changes |
| Activity returns after at least 18 hours away | A greeting; warmer animation after 7 days away | Immediate opportunity |
| A new explicit error kind appears | A grounded error remark | Immediate opportunity |
| A celebration ends **and the shared state returns to idle** | A brief completion remark | Immediate opportunity; not every turn end |

Unchanged tool activity does not call the model. There are no timed check-ins.
A context change clears obsolete scope immediately; an empty desk requires no call.
One display call runs at a time, with temporary remarks ahead of pending scope.
Superseded replies are discarded; requests/cards can cancel pending remarks.

Both kinds of text use projects, bounded first/latest user intent, lifecycle,
previous scope and five recent displayed remarks. Working/thinking/waiting
sessions participate, plus idle/error sessions active within 15 minutes, unless
removed earlier. Worktrees share project identity. Unknown intent stays unknown.

Apple Foundation Models runs locally when available, with a 5-second deadline
and no cloud fallback. Scope appears on both screens; temporary remarks appear on the device. Scope is
limited to 120 UTF-8 bytes; temporary remarks to
63 bytes and 4 seconds. Both are optional and English-only, independently of the
app's English/Korean interface. Invalid, unavailable or timed-out output leaves
Boop silent. Attention takes priority; text never wakes the device.

The editable guide is in Settings → Edit buddy behavior…. Changes apply on the
next decision; existing owner edits are preserved. See [Voice](UX-VOICE.md) for
input/privacy bounds. Reliable whole-desk meaning is still an open evaluation
gate. Richer check-result reactions and memory callbacks are [planned](UX-WORK-SCOPE.md).

## 6. Personality and memory

| Mechanism | Current behavior |
| --- | --- |
| Personality | Defined directly in the editable Markdown guide |
| Task intent and displayed scope | In memory only; no durable scope history or raw prompt storage |
| Recent display remarks | Last five, in memory, to discourage repetition |
| Reduced facts | Kept locally for 30 days |
| Private reflection | Once daily after 20 inactive minutes on AC; considers evidence through the previous day |
| Learned profile | Up to five new evidence-backed lines per reflection; inspect/clear in Settings |

Reflection uses at most 100 facts and 20 existing profile lines. Invalid or
unavailable results leave the profile unchanged. Approval decisions are excluded.
The current shared display context **does not yet use the learned profile or
episode memories**. Numeric traits and bond values are inactive.

## 7. Native approvals and attention reminders

Boop mirrors only reliably reported passive requests. Ordinary activity and
execution gates do not prove someone is waiting for the user. Native Codex
approval waiting cannot reliably be mirrored.

| Time since request | Reminder |
| --- | --- |
| Arrival | Amber face/footer |
| 60 seconds | First visual nudge |
| 120 seconds | Stronger visual nudge; no recurring final reminder |
| Snoozed/dismissed | Suppress reminders for that request until it clears; new requests start fresh |

Mac “Snooze reminder” leaves the request pending. Device dismissal also hides
its card locally, and repeated heartbeats do not reopen that same card. Neither
action answers the request. Quiet mode mutes all authored sounds while leaving
visual timing unchanged; the supported board has no speaker.

Old approval hooks return passthrough immediately, even with stale enabled
settings. Passthrough means continue to the editor's own approval flow.
Details: [Help](UX-HELP.md).

## 8. Where to find things

| Surface | What it provides |
| --- | --- |
| Mac menu bar | Static icon; filled when an agent needs you; click to open |
| Mac Overview | Status, optional scope, requests/errors, all sessions, device status, XP and activity grid |
| Mac Settings | Name, UI language, Quiet mode, pairing/firmware, agent hook setup/repair, login, profile/guide, support and app updates |
| Device at rest | Face, optional scope above it, working count below; no persistent Last finished row |
| Device face tap | Threads/history when work or recent completions exist; otherwise affection |
| Device detail pages | Three rows per page; Next advances, other taps return to the face |
| Device travel stats | Last synced name, XP, streak, days together and turn totals |

The Mac does not open itself for events. It keeps every session scrollable; the
device receives a bounded preview of up to 12 sessions and 6 recent completions,
with totals/omissions shown. Appearance is fixed. There is no Activity pane,
share export, collection, leaderboard, scheduled Quiet mode or quick-command action.

For exact controls, screen priority, brightness and connection behavior, use
[Device UX](UX-DEVICE.md). For navigation and update outcomes, use [Mac UX](UX-APP.md).
