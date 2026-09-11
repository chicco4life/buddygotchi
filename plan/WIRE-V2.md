# RenderState v2

Desktop policy sends fixed volume step 1 (0 while quiet), default skin, no accessory
and default silhouette. Retired commands are ignored as described below.

Host → device: one JSON object per line, frame cap 1536 bytes including newline.
Absent keys mean "none / unchanged". Every string is byte-capped on a character
boundary (`prefix(utf8Bytes:)`). Field names and enum raw values are exact.

| key | type | values / cap |
|---|---|---|
| `v` | int | always `2` |
| `state` | string | `asleep` `idle` `working` `needsYou` `done` `uhoh` |
| `effort` | string | `light` `hard` `grinding` (working only) |
| `cheer` | string | `hop` `cheer` `dance` (done only) |
| `uhoh` | string | `error` (uhoh only); old `stuck`/`hungry` frames normalize to `error` |
| `overlay` | string | `greet` `boop` |
| `greetLevel` | int | 0–3 |
| `dots` | int | 0–5 |
| `dotAlert` | int | index into dots, or absent |
| `card` | object | `{"id":≤23B,"tool":≤23B,"gloss":≤63B,"stakes":"fine"\|"checkIt"\|"careful","n":int,"of":int,"approval":bool}` for needs-you; `{"kind":"pair"\|"update","text":≤63B}` for system cards |
| `bubble` | string | ≤ 63 bytes |
| `scope` | string | ≤120 UTF-8 bytes, persistent while connected; omission clears; overflow omitted whole |
| `gift` | bool | retired: host always sends false for older firmware |
| `giftLine` | — | retired: omitted by host, ignored by receiver |
| `focus` | bool | Legacy name for sound-only Quiet mode; no visual effect or sound exceptions. |
| `mute` | int | 0 = mute, 1–3 volume step |
| `posture` | string | `desk` `perch` `travel` (optional override) |
| `cosmetic` | object | `{"skin":≤15B,"accessory":"sprout"\|"scarf"\|"crown","silhouette":"round"\|"tall"}`; each identifier ≤15B |
| `snap` | object | `{"name":≤23B,"level":int,"xp":int,"xpNext":int,"streak":int,"best":int,"days":int,"tasks":int,"today":int,"biggest":"hop"\|"cheer"\|"dance"}` |
| `agent` | retired | Never emitted; new firmware ignores historical agent payloads. |
| `t` | int | host unix time in ms |

Accessory and silhouette vocabularies are closed. Omitted or empty identifiers
select the bare/default shape; unknown identifiers render the same fallback.
Omitting the entire `cosmetic` object preserves the cached cosmetics. Skin
identifiers tint body and field; unknown skins use neutral grey.

Host → device command (USB or secured BLE): `{"cmd":"retire"}`. No `v` is
required. The device fades over 2400 ms with one blink at 600–850 ms, ignores
state frames during the fade, and then emits `{"ack":"retire"}`. Completion
clears the unit key, snapshot, cosmetics, volume, first-wake completion flag
and transient model (see Signing below for key renewal). The display stays black until a subsequent accepted frame or reboot
starts a new creature. BLE bonds and crash diagnostics are retained. Repeated
retire commands during the fade or while retired are ignored.

Device → host: one JSON object per line.

| command / reply | JSON shape |
|---|---|
| retired decision | `decision` and legacy `permission` commands are ignored; no editor action |
| retired commands | `collect` and `quick` are ignored; no event, award or action |
| boop | `{"cmd":"boop","hold":bool}` |
| posture | `{"cmd":"posture","p":"desk"\|"perch"\|"travel"}` |
| motion | `{"cmd":"motion","m":"shake"\|"flip"\|"pickup"}` |
| battery | `{"cmd":"battery","pct":int,"charging":bool}` |
| focus | `{"cmd":"focus","on":bool}` |
| retire completion | `{"ack":"retire"}` |
| ack | Existing `{"ack":…}` replies |
| status | Existing `{"cmd":"status"}` reply, now also carrying `"board"` and `"contract":2` |
| legacy (one release) | `{"cmd":"permission","id":"…","decision":"allow"\|"deny"}` and `{"cmd":"boop"}` without `hold` |

Shedding order when a frame exceeds 1536 bytes: remove `scope` whole, then `snap`, then
`cosmetic`, then truncate `bubble` on character boundaries until
it fits. Assert the cap including the newline.

## Retired signing

Leaderboard signing is deferred. Firmware no longer generates a unit key or
handles `unit` / `sign`; the host ignores legacy replies. Those telemetry
fields and USB commands are removed. BLE bonding, status, OTA and retirement
of creature data remain. Existing unused key blobs are not read.

`snap.tasks` counts completed turns. `snap.rest` is no longer sent; old
firmware defaults it to zero. Current firmware accepts the legacy value as an
unused compatibility field. No rest-day behavior remains.

## Quiet mode

Owner decision: `focus` and `cmd:focus` keep their v2 names for compatibility but
now mean Quiet mode only. All beeps are suppressed when true, including errors.
The host also sends `mute:0` while quiet, using fixed default volume step 1 when unmuted.
Visual states, nudges, rendering and animation timing do not depend on this flag.
Deploy the matching firmware to remove the former visual Focus marker and old
sound exception. Former scheduled Focus hours are ignored by the host.

## Nudges

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

## Optional agent availability counts

`agents` is an optional array of at most four unique rows:
`{"source":"codex","working":2,"idle":1}`. Source is one of `codex`,
`claude-code`, `cursor`, `other`; both counts are required integers 0–99.
The host emits stable source order and clamps each displayed count to 99.
Unknown harnesses aggregate as Other. Missing/empty agents clears all counts;
these are live state, never persisted. Invalid types, duplicate sources,
unknown source tokens and out-of-range counts reject the entire frame.
Older firmware ignores the additive field; older hosts retain face-only behavior.
The 1536-byte frame cap is unchanged.

## Additive glance fields

`threads`: at most 12 compact arrays `[source, status, title]`, with source
0 Codex / 1 Claude / 2 Cursor / 3 Other; status 0 idle / 1 working / 2 needs you /
3 error. `threadTotal` includes rows outside the bounded preview. `recent` holds
up to six `[sequence, source, title]` completed turns, newest first.
`notice`: optional object `{id, count, age, left, cheer}`; id is the first
completion sequence in the batch, age/left are milliseconds, left <= 8000,
cheer is hop/cheer/dance. Host monotonic time owns coalescing and cooldown;
firmware uses its local monotonic deadline and never extends repeated frames.
Omission clears ephemeral fields. Titles <=47 UTF-8 bytes, no control characters.
These fields stay inside the existing 1536-byte newline-inclusive frame cap:
drop snapshot/cosmetics first, then oldest history/preview rows as necessary;
retain at least the newest completion and expose threadTotal. Reconnect may show
Last finished but must not replay a notice already in progress.
