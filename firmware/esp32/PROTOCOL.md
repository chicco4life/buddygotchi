# Boop device protocol — RenderState v2

The shared host contract is [plan/WIRE-V2.md](../../plan/WIRE-V2.md).
This document describes the firmware receiver and USB diagnostics.

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
| `uhoh` | error, stuck, hungry |
| `overlay` / `greetLevel` | greet or boop / integer 0–3 |
| `dots` / `dotAlert` | integer 0–5 / optional zero-based index into dots |
| `card` | decision `{id,tool,gloss,stakes,n,of,approval}` or system `{kind,text}` |
| decision card | id/tool ≤23 B, gloss ≤63 B, stakes fine/checkIt/careful, approval boolean |
| system card | kind pair/update, text ≤63 B |
| `bubble` | ≤63 B, four seconds; unchanged heartbeats do not restart it |
| `gift` / `giftLine` | boolean / ≤40 B, collected locally until host clears or replaces it |
| `focus` / `mute` | boolean / integer 0–3 |
| `posture` | desk/perch/travel; omission restores IMU detection |
| `cosmetic` | skin/accessory/silhouette ≤15 B each; closed vocabularies and fallback in [WIRE-V2](../../plan/WIRE-V2.md) |
| `snap` | name, level, xp, xpNext, streak, best, rest, days, tasks, today, biggest |
| snapshot storage | nonnegative 32-bit counters including rest; name/biggest ≤63 B |
| `agent` | name ≤23 B, color ≤15 B, emotion ≤23 B, say ≤63 B; suppressed with a card |
| `t` | nonnegative 64-bit host epoch milliseconds; synchronizes the HAL clock |

All string caps are bytes. The firmware rejects overflow rather than chopping
an approval ID or a UTF-8 character. The host supplies valid UTF-8. Snapshot,
cosmetic identifiers, volume and the first-wake flag live in `creature-v2` NVS;
writes occur only on changes. No prompt, bubble or gift persists across reboot.
The old species/name/owner storage is neither read nor written.

```json
{"v":2,"state":"needsYou","dots":1,"mute":1,"card":{"id":"req_1","tool":"Bash","gloss":"Run tests","stakes":"checkIt","n":1,"of":1,"approval":true}}
```

Cards arm 600 ms after arrival. A press must start after arming and belong to
the same ID on release. Ordinary tap allows; primary hold ≥1 s or secondary
tap denies. Careful requires primary hold ≥2 s to allow; a tap shakes the head.
After deciding, feedback is `sending...`, then `no link?` after three seconds.
Only an accepted frame without the answered ID confirms `yes!`/`okay`.
A different new card takes priority over that confirmation. After ten seconds
without acknowledgement, a live card is rearmed. Link loss is not an ack.

## Device → host

```json
{"cmd":"decision","id":"req_1","d":"allow"}
{"cmd":"decision","id":"req_1","d":"deny"}
{"cmd":"collect"}
{"cmd":"boop","hold":false}
{"cmd":"quick"}
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
focus at 1 s, “night night” at 3 s, off after the 600 ms farewell or release.
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
A level increase shimmers for 900 ms then reveals a cosmetic supplied in
the same or next frame over 600 ms. Streak 7/30/100 pulses for 1500 ms.
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

## Signing

Prototype keys are generated on-device on the first boot with no key, in
`setup()` before HAL/ADC/BLE initialization. No host supplies a private key.
The shipped ESP-IDF 5.5.4 / mbedTLS 3.6.5 has no Ed25519 `mbedtls_pk` key type,
so this build reports **`alg: "p256"`**, using `mbedtls_ecdsa` on secp256r1.
The hardware noise source is enabled while `esp_random()` seeds CTR-DRBG,
then disabled before HAL/RF use. The private scalar is a 32-byte big-endian
NVS blob `unit/private`; the public key is the adjacent `unit/public` blob.
Private material is never sent to the host; temporary crypto buffers are
cleared/freed after use. Incomplete or invalid stored keys fail closed and
require explicit debug regeneration; boot never silently replaces them.

USB or secured BLE, newline JSON (no `v` required):

```json
{"cmd":"unit"}
{"ack":"unit","ok":true,"unit":"<hex16>","pub":"<base64>","alg":"p256"}
{"cmd":"sign","day":"2026-09-09","xp":1234,"nonce":"0123ABCDef"}
{"ack":"sign","ok":true,"unit":"<hex16>","day":"2026-09-09","xp":1234,"nonce":"0123ABCDef","sig":"<base64>"}
```

`pub` is the **65-byte SEC1 uncompressed P-256 point** (`04 || X || Y`),
base64 encoded. `unit` is the first eight bytes of SHA-256 of those exact
public-key bytes, encoded as 16 lowercase hex digits. `sig` is base64 of an
**ASN.1 DER ECDSA signature using SHA-256**, covering the exact ASCII bytes
`unit|day|xp|nonce`, without spaces or a newline. `xp` uses canonical decimal
notation; nonce letter case is preserved. If a future build reports
`ed25519`, its public key is 32 raw bytes and its signature is 64 raw bytes
covering that same message directly.

Validation: `day` must match ASCII `YYYY-MM-DD` (pattern only, not calendar
validation); `xp` must be a JSON integer from 0 through 9223372036854775807;
`nonce` must contain 2–64 hex characters, in complete byte pairs. Missing
fields, booleans, floats, embedded NULs and wrong types are rejected.
Failures return `{"ack":"sign","ok":false,"error":"..."}` with
`invalid_day`, `invalid_xp`, `invalid_nonce`, `rate_limited`,
`key_unavailable_reboot`, or `sign_failed`. There is at most one signing
attempt per 1000 ms per device across both transports, measured from attempt
start on the real monotonic clock; animation clock commands cannot bypass it.
Invalid fields do not consume the allowance. Reboot resets the limiter.
This signs a host-supplied total, not an independently validated XP ledger.

`status` gains `unit` and `alg`; `ping` also reports `keygenMs` (generation
and persistence elapsed milliseconds on this boot, zero when loading an
existing key). When identity is unavailable, status reports an empty `unit`
and the `unit` command returns `ok:false`, `error:"key_unavailable_reboot"`.

Retire completion clears the key along with creature data. Until the next
reboot, `unit`/`sign` report key unavailable, even if a frame wakes the display.
The replacement key is generated only by `setup()` on that reboot; there is
no key generation in rendering or command handling. `firstwake reset`
**preserves** the key. USB-only debug `unit` prints the same reply as JSON
`unit`; `unit regen` prints a destructive-identity warning, clears the key,
and reboots to generate its replacement. If clearing fails it reports an
error and does not reboot. A retire clear failure reports
`{"ack":"retire","ok":false,"error":"key_clear_failed"}`.

Host tools (from `firmware/esp32`):

```sh
python3 tools/buddyctl.py unit --json > unit.json
python3 tools/buddyctl.py sign --day 2026-09-09 --xp 1234 --json > reply.json
python3 tools/verify_sig.py --unit unit.json reply.json
```

`sign` creates a random 16-byte nonce unless `--nonce <hex>` is supplied.
The verifier requires a **trusted** unit reply from the device/provisioning
channel and checks identity derivation, field limits and signature; it exits
0 for valid, 1 for invalid, and 2 for input/dependency errors. Python has no
standard-library ECDSA/Ed25519 verification API; install the host dependency
with `/tmp/hilvenv/bin/python -m pip install cryptography` when network or a
local wheel is available, then use that interpreter for verification/HIL.
No additional firmware library is used. The HIL signing/retirement tests in
`tests/hil/test_usb.py` need a disposable bench creature; they reboot and
retire it. Offline host checks:
`python3 -m unittest discover -s tests/host -v`.

Session `dots` and `dotAlert` are still validated and reported for wire
compatibility, but are not rendered. Omit `dotAlert` when there is no alert;
an explicit `-1` is not a valid incoming index.
