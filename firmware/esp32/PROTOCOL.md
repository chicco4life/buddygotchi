# Boop device protocol — RenderState v2

## Current policy

Current desktop policy sends fixed volume step 1 (0 while quiet) and default appearance with no accessory. The host ignores legacy `quick` gestures. Legacy wire names remain compatible.

The shared host contract is [plan/WIRE-V2.md](../../plan/WIRE-V2.md).
This document describes the firmware receiver and USB diagnostics.

Gifts/collection and quick commands are
removed. The host sends `gift:false` for old firmware, ignores incoming
`collect`/`quick`, and omits `giftLine`. New firmware ignores both gift fields
and normalizes old stuck/hungry variants to ordinary error. Wire version stays 2.

USB serial and encrypted BLE Nordic UART carry one JSON object per line.
Maximum frame size: **1536 bytes excluding newline**. Each transport has its
own fixed buffer, discarded whole on overflow and reset after a two-second
partial-line gap. A BLE disconnect also clears its partial line. Input drains
are bounded per loop so a flooded port cannot monopolize rendering.

## Host → device

A state frame requires integer `v: 2`. Missing/wrong versions, including old
`pet` frames, retain the last good model and increment `badFrames`. Malformed
JSON, wrong types, out-of-range numbers and over-cap strings are also rejected
atomically. Unknown keys and unknown commands are ignored. A recognized enum
with an unknown string value retains that field's previous value. Omitted
transient fields clear; omitted `state` renders asleep. Omitted `snap` and
`cosmetic` leave their persistent caches intact. Omitted `mute` means 0.

| Key | Values / byte cap |
| --- | --- |
| `state` | asleep, idle, working, needsYou, done, uhoh |
| `effort` | light, hard, grinding |
| `cheer` | hop, cheer, dance |
| `uhoh` | error; legacy stuck/hungry normalize to error |
| `overlay` / `greetLevel` | greet or boop / integer 0–3 |
| `dots` / `dotAlert` | integer 0–5 / optional zero-based index into dots |
| `card` | passive attention `{id,tool,gloss,stakes,n,of,approval}` or system `{kind,text}` |
| attention card | id/tool ≤23 B, gloss ≤63 B, stakes fine/checkIt/careful, approval boolean |
| system card | kind pair/update, text ≤63 B |
| `bubble` | ≤63 B, four seconds; unchanged heartbeats do not restart it |
| `gift` / `giftLine` | retired, ignored; diagnostics report gift=false |
| `focus` / `mute` | boolean / integer 0–3 |
| `posture` | desk/perch/travel; omission restores IMU detection |
| `cosmetic` | skin/accessory/silhouette ≤15 B each; closed vocabularies and fallback in [WIRE-V2](../../plan/WIRE-V2.md) |
| `snap` | name, level, xp, xpNext, streak, best, days, tasks, today, biggest |
| snapshot storage | nonnegative 32-bit counters; name/biggest ≤63 B |
| `agent` | Retired; ignored for compatibility. No agent-expression renderer remains. |
| `t` | nonnegative 64-bit host epoch milliseconds; synchronizes the HAL clock |

All string caps are bytes. The firmware rejects overflow rather than chopping
an approval ID or a UTF-8 character. The host supplies valid UTF-8. Snapshot,
cosmetic identifiers, volume and the first-wake flag live in `creature-v2` NVS;
writes occur only on changes. No prompt or bubble persists across reboot.
The old species/name/owner storage is neither read nor written.

```json
{"v":2,"state":"needsYou","dots":1,"mute":1,"card":{"id":"req_1","tool":"Bash","gloss":"Run tests","stakes":"checkIt","n":1,"of":1,"approval":false}}
```

Cards arm 600 ms after arrival. A press must start after arming and belong to
the same ID on release. Ordinary primary tap allows; secondary hold ≥1 s denies. Careful requires primary hold ≥2 s to allow; a tap shakes the head.
After deciding, feedback is `sending...`, then `no link?` after three seconds.
Only an accepted frame without the answered ID confirms `yes!`/`okay`.
A different new card takes priority over that confirmation. After ten seconds
without acknowledgement, a live card is rearmed. Link loss is not an ack.

## Device → host

```json
{"cmd":"boop","hold":false}
{"cmd":"posture","p":"perch"}
{"cmd":"motion","m":"pickup"}
{"cmd":"battery","pct":80,"charging":true}
{"cmd":"focus","on":true}
```

Motion values are shake/flip/pickup. Postures are desk/perch/travel. Battery
reports on change and on a live/secure connection. `{"cmd":"status"}` returns
an `ack: "status"` with `ok`, `board`, `contract:2`, `fw`, `git`, `name`, `secure`.
OTA retains `ota_begin`, `ota_chunk`, `ota_end` and existing ack envelopes;
see `firmware/ota.h`. Character transfer is removed.

## USB debug

All keys in the diagnostic envelopes below are device-only telemetry, not
additional host-to-device RenderState fields.

- `ping` → `<<PONG {...}>>`: version, board, contract, uptime, heap, largest
  allocation, minimum heap, present timing and crash telemetry. `usbOnly` is
  true only for the compile-time `ws-amoled164-usb-debug` build; normal
  firmware reports false. Older firmware omits it and is not USB-isolated.
- `state` → `<<STATE {...}>>`: contract, creature, effort, cheer, uhoh, overlay,
  card/cardId/armed, visible bubble, gift, focus, posture, dots, mute, screenOff,
  brightness, presence, napping, dizzy, frozen, badFrames and crash telemetry.
  Also includes layer, feedback, stats/page/cache facts, sound/count/note,
  firstWake, rtcValid, transport counters and shutdownStage for HIL.
- `clock <ms>` freezes presentation/model time; `clock clear` resumes it.
  Springs stop integrating while frozen. Entry/resume translate timer origins
  to preserve their ages; subsequent frozen clock steps simulate elapsed time.
  `t` synchronizes wall time, not this clock. Transport timeouts, physical press durations, watchdog and uptime
  keep real time so debug freezes cannot disable recovery or fake a hold.
- `press a|b|m <20–10000 ms>` injects a real-duration press. `btn a|b|m` is a
  120 ms press through the same guards. a=primary, b=secondary, m=secondary alias.
- `imu`, `imu set <ax> <ay> <az>`, `imu clear`: g-units, real detector path.
- `screenshot`: RGB565LE base64 between `SCR_BEGIN W=… H=… ROT=… FMT=RGB565LE`
  and `SCR_END LEN=… CRC32=…`; the watchdog is fed while streaming.
- `reboot`, `deepsleep [timer-ms]`, `clearbonds`, `guardclear`, `hang` retain
  their diagnostic roles. `hang` deliberately exercises watchdog recovery.

The normal screen dims after 120 s of inactivity, with an orb glow floor.
Asleep and face-down nap use brightness 8; pending cards use 220. The screen
never switches off automatically. Only the secondary shutdown hold does so:
Quiet mode (`focus` compatibility command) at 1 s, “night night” at 3 s, off after the 600 ms farewell or release.
A wake press consumes the action. Explicit `deepsleep` is a diagnostic escape.

## Phase 6 rituals and appearance

The host `retire` command, completion acknowledgement, reset scope, and
closed cosmetic vocabularies are defined in [WIRE-V2](../../plan/WIRE-V2.md).
The fade uses panel brightness; its completed screenshot buffer is black.

USB `firstwake reset` replies `<<FIRSTWAKE reset>>`, re-arms the persistent
wake flag and restarts its animation without deleting the snapshot. Grey
lasts until a validated frame explicitly supplies nonempty `cosmetic.skin`
or has a non-asleep state. The 600 ms color sweep completes the wake flag;
a reboot before completion still wakes grey. Wake choreography: sleep to
1200 ms, first eye to 2200, both eyes, blinks at 2600/2920, recognition at
3200, alternating corner glances from 4000 ms.

Additional device-only USB diagnostic `state` keys (not RenderState fields): `ritual` (`firstWake`, `greet`, `levelUp`, `streak`,
`retire`, `none`), `grey`, `colorProgress` (0–1), `cosmeticProgress` (0–1),
`accessory`, `silhouette`, `level`, `streak`, `pickup`, and `pose`.
Perch poses are `dangle`, `lean`, `grip`, `peer-tip`, `hop`, `jump-land`,
`sag`, `curl`, `pop-up`; desk/travel report the state, and pick-up reports
`pickup` for 1000 ms. Card priority suppresses pick-up and growth rituals.
Level increases are ignored; level-up effects are retired. Streak 7/30/100 pulses for 1500 ms.
Greet lasts 2200 ms with four sizes (wire range remains 0–3).

Appearance identifiers and unknown-value fallbacks follow [WIRE-V2](../../plan/WIRE-V2.md). Dots render in the bottom margin for every
state/layer, with four circles and a plus for the fifth, including alert tint.

Capture offsets (`clock settle N`, relative to state entry or reset/motion):
`first-wake-grey` 4500; `greet-0..3` 700; `levelup`, `streak-7` 450;
`pickup` 300; `perch-done-dance` 600; all other new cells 2500 ms.
`tools/shot_cells.py` owns the setup recipes and offsets. First wake resets
after the asleep frame; growth uses level 1/streak 0 baseline then a target
frame; pickup injects `(0.7,0,0.7)` after a still baseline. Captures explicitly
settle the pose, so timing of host serial reads does not affect the pixels.

## Removed signing extension — 2026-09-11

Leaderboard signing is deferred. Firmware no longer generates a unit key or
handles `unit` / `sign`; the host ignores legacy replies. Those telemetry
fields and USB commands are removed. BLE bonding, status, OTA and retirement
of creature data remain. Existing unused key blobs are not read.

`snap.tasks` counts completed turns. `snap.rest` is no longer sent; old
firmware defaults it to zero. Current firmware accepts the legacy value as an
unused compatibility field. No rest-day behavior remains.

## Quiet mode (2026-09-10)

The v2 `focus` boolean and `cmd:focus` name are retained but now mean sound-only
Quiet mode. Suppress every motif, including Uh-oh, and stop an in-progress tone.
Do not draw a Focus marker or change expressions, motion, nudges, or timing.
The host persists the toggle and sends mute=0 while quiet; unmuting restores its
fixed default volume on the next frame. Diagnostic field/stage names remain unchanged.

## Nudge projection — 2026-09-11

Host frames carry `nudgeRung: 0|1|2`, zero outside needs-you. Missing means zero;
invalid values reject the frame. Old firmware ignores this additive field.
For the same visible request, rising rungs play one reminder: soft at rung 1,
stronger at rung 2. Repeated heartbeats do not replay it. A lean marks a nudge;
rung 2 strengthens the amber pulse. Quiet mode retains visuals without sound.
Local passive-card dismissal suppresses reminders for that card; a new ID
resets dismissal. Host passive-request expiry remains 290 seconds. Approval decisions are retired.

## Native approvals and passive cards — 2026-09-11

Buddy no longer handles approval decisions. The host emits `approval:false`
and the neutral legacy `stakes:"checkIt"` for every attention card. No command
classification runs. Current firmware normalizes an incoming legacy approval
flag to false and renders no stakes dot, yes/no labels, hold progress or decision
feedback. It never sends approval decisions. Host ignores old decision and
permission messages. Legacy wire fields remain for older firmware compatibility;
BLE, pairing and OTA acknowledgements are unchanged. Deploy the matching app
and firmware to remove the old device approval presentation completely.

Attention dismissal, 60/120-second nudges and Quiet mode remain. A stale hook
approval call gets immediate native passthrough, not allow or deny.

Growth update: `snap.xp` is cumulative earned XP; `tasks` counts completed agent turns.
`level` and `xpNext` remain compatibility fields sent as 1 and 0, respectively.
They have no display or animation effect. The daily activity grid is Mac-only;
no history array is sent to the device. Existing wire integer ranges are unchanged.
