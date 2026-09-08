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
clears the snapshot, cosmetics, volume, first-wake completion flag and transient
model. The display stays black until a subsequent accepted frame or reboot
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
