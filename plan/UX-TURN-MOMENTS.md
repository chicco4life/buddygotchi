# Turn moments through the shared behavior guide

Implemented in the development source, 2026-09-12. This replaces mid-work device
scope pop-ups and independent completion notices/after-idle remarks. See
[PLAN.md](PLAN.md) for built, tested and installed status.

## One existing path

`trigger → bounded BehaviorContext + BEHAVIOR.md → shared Voice → validated core
moment → outputs`

The existing guide loader supplies both declarative presentation policy and model
prose. The engine passes policy to pure Core; Core detects observable lifecycle
facts, tracks identity/milestones, coalesces, cancels and expires. Voice uses the
existing single display worker, ahead of Mac summary requests. No separate start,
greeting or exasperation service, classifier or model lane exists.

The model still returns text or SILENT. The guide's policy selects supported
expressions; firmware implements their motion. The model cannot execute code,
change XP, answer approvals, create arbitrary animation or extend a deadline.

## Trigger opportunities

| Trigger | Behavior and default timing |
| --- | --- |
| First work signal for a distinct turn | Small nod and a short acknowledgement, 1.5 seconds. Known intent can inform wording. Subsequent tools do not repeat it. |
| A started turn completes | One moment sized by measured duration, even if other tasks remain busy. No delayed second remark. |
| Active turn crosses 5 or 15 minutes | Optional gentle exasperation/patience and weary expression, 4 seconds. Two-minute desk cooldown. |
| Person interacts after 18 hours away | Optional contextual greeting and wave, 4 seconds. A simultaneous start merges this into its one 1.5-second opportunity. |
| Explicit error | Existing grounded error remark in the same Voice lane; no successful-completion reaction. |
| Settled work-context change | Mac summary only, with existing two-second debounce. No device remark. |

Long-work opportunities are keyed to the active turn, consumed once per threshold,
and removed at completion/removal. Waiting/request/error opportunities are consumed
without speaking, so they cannot replay later or pressure someone to approve.
Only working/thinking sessions may show them. There is no model call on every tick.

Person return tracking uses an optional persisted `lastInteractionAt` from explicit
turn starts and boops, separate from background activity's `lastSeenAt`. Existing
memory decodes without it. First launch with no prior interaction is not an absence.
The event supplies measured absence, local hour/time-of-day and bounded intent;
no inference about sleep, fatigue or usual habits is justified by the timestamp.

## Completion tiers

Duration runs from the first work signal through turn completion, including waits.
It is a proxy for effort, not a semantic difficulty score. Working effort and XP
accounting remain unchanged. A terminal failure closes its duration; a later retry
starts fresh. Duplicate endings, cleanup and failures do not celebrate.

| Turn duration | Device presentation | Dwell including fades |
| --- | --- | --- |
| Under 3 seconds | Pleased `^_^` face only; no text request or background wash | 1.2 seconds |
| 3 to under 20 seconds | Face lifts 28 px and shrinks 14%; 24 px caption below; existing teal/sage wash | 4 seconds |
| 20 seconds or more | Compact happy face; both hands pull the 32 px caption up and release it | 5 seconds |

Exactly 3 seconds uses the middle tier; exactly 20 seconds uses the full tier.
The full caption arrives over 700 ms with a small settling bounce, then hands
release between 750 and 1100 ms. The optional batched count waits until arrival
finishes. Face remains prominent and text has 24 px side margins.

Completions during an active moment share its ID, increment count and retain the
latest two titles as bounded context. The highest tier wins; motion never restarts.
An upgrade extends toward the larger tier's dwell, while equal/lower arrivals
allow a short tail (default 2 seconds), all capped at 8 seconds from original start.
After expiry, a 3-second cooldown records history without another moment.
Completion says the turn ended; “tests passed” needs separate supplied evidence.

## Guide policy

Edit the existing `BEHAVIOR.md` via Settings → Edit buddy behavior…. The bundled
[source guide](../app/Boop/Resources/BEHAVIOR.md) contains the complete initial
`boop-policy` fenced JSON object; its prose controls wording, warmth and silence.
All times below are milliseconds.

| Key | Default | Meaning / validation |
| --- | --- | --- |
| `captionAfterMs`, `fullAfterMs` | 3000, 20000 | Strictly increasing positive duration boundaries |
| `faceMs`, `startMs`, `remarkMs` | 1200, 1500, 4000 | Face-only, start, and return/long-work dwell |
| `captionMs`, `fullMs` | 4000, 5000 | Completion caption/full dwell |
| `batchMaxMs`, `batchTailMs` | 8000, 2000 | Total completion ceiling; equal/lower arrival tail |
| `cooldownMs` | 3000 | Completion cooldown |
| `returnAfterMs` | 64800000 | Person absence threshold, at least 60000 |
| `longAfterMs` | [300000, 900000] | Up to three unique ascending milestones, each at least 60000; [] disables |
| `longCooldownMs` | 120000 | Desk-wide long-work cooldown, at least 60000 |
| `expressions` | start:nod, completed:pleased, full:pull, longRunning:weary, returned:wave | Values from nod/pleased/weary/wave/pull only |
| `fallbacks` | start:"On it!", completed:"Turn finished.", returned:"Welcome back!" | Optional immediate phrases; long-work fallback absent |

Dwell/tail values must be 500–8000; batch ceiling is at most 8000 and at least
the caption/full dwell. All numeric values must be finite, nonnegative and no
larger than seven days. Known dictionary keys are the occasions above (fallbacks
exclude full, which uses completed). Fallback storage is capped at 48 characters,
63 UTF-8 bytes, without newlines; each use also passes its occasion's tighter fit.

Missing top-level fields inherit bundled policy. Supplied dictionaries replace
the corresponding dictionary; `{}` disables its fallbacks. Unknown keys, malformed
JSON/types or invalid policy values fall back atomically to bundled policy while
preserving owner prose. The normal guide override size/read checks still apply.
Policy is reread on events; future opportunities use new settings, existing
issued deadlines do not restart. Code defaults exist only as a last-resort policy
if bundled resources are unavailable. Owner files are never overwritten.

## Text, motion and interruption

Start/return/long-work: one line, at most 24 printable ASCII characters/bytes.
Completion: two lines, at most 48. Host and device also validate 408 px word-wrapped
width at the actual size (24 px captions, 32 px full text). Existing transport
storage is 63 bytes. Unsupported glyphs, long words, excess lines or bytes mean
silence, never shrinking or clipping. All phrases exceed the 16 px bottom-right
busy/idle hint in size. The normal hint remains fixed through caption fades;
low battery uses the left side when it is present.

Optional guide fallbacks display immediately. Timely valid generation replaces
them; SILENT clears words and invalid fitted text stays silent. Late/unavailable generation
leaves the fallback/face only until normal expiry. Replies match ID, count and
deadline: a fast completion cancels its start reply and a late completion cannot
reopen its animation. Tiny completions never request words.

Requests/errors, system cards, details, stats and other remarks win over moments.
Sleep, nap, display-off or disconnection also consume them. No moment wakes the
device, queues for later or restarts on a keepalive. First reconnect establishes
a baseline without replay; a new ID may show identical words from a different
turn. The additive wire contract is [moment](WIRE-V2.md#additive-turn-moments).

## Acceptance and remaining live gates

Pure and engine tests cover exact boundaries, event identity, failed retries,
coalescing, reply cancellation, guide changes/fallback, bounded milestones,
return+start merging and text/wire limits. USB checks cover deadlines, interruption,
repeated frames, malformed input and hint stability. Lifecycle screenshots cover
all occasions and intermediate full-caption pulling/release poses; affected/new
goldens are reproduced independently. Restore the saved normal firmware afterward.

A bounded Foundation Models replay exercises synthetic context and output budgets;
broad semantic quality, production Bluetooth with this pair, owner guide wording
and real native-editor triggers remain separate gates. See [Verification](VERIFICATION.md#turn-moments)
and the dated evidence. No webcam verification without explicit session opt-in.
