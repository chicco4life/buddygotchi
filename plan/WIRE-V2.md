# RenderState v2

Host → device: one JSON object per line, frame cap 1536 bytes including newline.
Absent keys mean "none / unchanged". Every string is byte-capped on a character
boundary (`prefix(utf8Bytes:)`). Field names and enum raw values are exact.

| key | type | values / cap |
|---|---|---|
| `v` | int | always `2` |
| `state` | string | `asleep` `idle` `working` `needsYou` `done` `uhoh` |
| `effort` | string | `light` `hard` `grinding` (working only) |
| `cheer` | string | `hop` `cheer` `dance` (done only) |
| `uhoh` | string | `error` `stuck` `hungry` (uhoh only) |
| `overlay` | string | `greet` `boop` |
| `greetLevel` | int | 0–3 |
| `dots` | int | 0–5 |
| `dotAlert` | int | index into dots, or absent |
| `card` | object | `{"id":≤23B,"tool":≤23B,"gloss":≤63B,"stakes":"fine"\|"checkIt"\|"careful","n":int,"of":int,"approval":bool}` for needs-you; `{"kind":"pair"\|"update","text":≤63B}` for system cards |
| `bubble` | string | ≤ 63 bytes |
| `gift` | bool | orb pending |
| `giftLine` | string | ≤ 40 bytes |
| `focus` | bool | |
| `mute` | int | 0 = mute, 1–3 volume step |
| `posture` | string | `desk` `perch` `travel` (optional override) |
| `cosmetic` | object | `{"skin":≤15B,"accessory":"sprout"\|"scarf"\|"crown","silhouette":"round"\|"tall"}`; each identifier ≤15B |
| `snap` | object | `{"name":≤23B,"level":int,"xp":int,"xpNext":int,"streak":int,"best":int,"rest":int,"days":int,"tasks":int,"today":int,"biggest":"hop"\|"cheer"\|"dance"}` |
| `agent` | object | `{"name":≤15B,"color":≤7B,"emotion":≤15B,"say":≤40B}`; never present together with `card` |
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
| decision | `{"cmd":"decision","id":"…","d":"allow"\|"deny"}` |
| collect | `{"cmd":"collect"}` |
| boop | `{"cmd":"boop","hold":bool}` |
| posture | `{"cmd":"posture","p":"desk"\|"perch"\|"travel"}` |
| motion | `{"cmd":"motion","m":"shake"\|"flip"\|"pickup"}` |
| battery | `{"cmd":"battery","pct":int,"charging":bool}` |
| focus | `{"cmd":"focus","on":bool}` |
| retire completion | `{"ack":"retire"}` |
| ack | Existing `{"ack":…}` replies |
| status | Existing `{"cmd":"status"}` reply, now also carrying `"board"` and `"contract":2` |
| legacy (one release) | `{"cmd":"permission","id":"…","decision":"allow"\|"deny"}` and `{"cmd":"boop"}` without `hold` |

Shedding order when a frame exceeds 1536 bytes: remove `snap`, then
`cosmetic`, then truncate `bubble`/`giftLine` on character boundaries until
it fits. Assert the cap including the newline.

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

USB diagnostic `ping.usbOnly` identifies the compile-time USB-only bench
build. It is not a RenderState field and does not change the production
wire contract. Missing or false means the test runner must not assume BLE
is disabled. See `firmware/esp32/PROTOCOL.md`.

Session `dots` and `dotAlert` are still validated and reported for wire
compatibility, but are not rendered. Omit `dotAlert` when there is no alert;
an explicit `-1` is not a valid incoming index.
