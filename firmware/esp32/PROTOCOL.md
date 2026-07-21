# Boop ESP32 Protocol

The desktop app sends newline-delimited JSON heartbeat frames over USB serial or
BLE Nordic UART RX. The device sends newline-delimited JSON replies over USB
serial and BLE Nordic UART TX. Heartbeat receivers keep one 2048-byte line
buffer per transport.

## Heartbeat Fields

| Field | JSON type | Mac wire max | Firmware destination / max | Meaning |
| --- | --- | ---: | --- | --- |
| `pet` | string | enum value | `TamaState.pet`, 11 chars | Overall pet state: `sleep`, `idle`, `busy`, `attention`, `celebrate`, `error`, or `thinking`. `thinking` renders as the busy/calm face. |
| `species` | string | current species name | `TamaState.species`, 15 chars | ASCII buddy species name. |
| `desktop` | string | enum value | `TamaState.desktop`, 15 chars | Desktop link state: `connected` or `disconnected`. |
| `total` | number | integer | `sessionsTotal`, uint8 | Total sessions known to the Mac app. |
| `running` | number | integer | `sessionsRunning`, uint8 | Sessions currently doing work. |
| `waiting` | number | integer | `sessionsWaiting`, uint8 | Sessions waiting for user approval. |
| `msg` | string | 23 chars | `TamaState.msg`, 23 chars | Short status/completion message. When disconnected, firmware sets `no agents awake`. |
| `celebrate` | boolean | boolean | `TamaState.celebrate` | Enables the celebrate state and the celebrate chirp when `pet == "celebrate"`. |
| `mute` | boolean | optional boolean | `TamaState.muted` | Suppresses state-transition chirps when true. Omitted means leave the current mute value unchanged. |
| `promptId` | string/null | uncapped by Mac | `promptId`, 39 chars | Pending permission request id. Non-empty arms approval buttons when `promptApproval` is true. |
| `promptTool` | string/null | 20 chars | `promptTool`, 23 chars | Tool name shown in the live approval strip. |
| `promptHint` | string/null | 60 chars | `promptHint`, 63 chars | Command/hint shown in the live approval strip. |
| `promptSource` | string/null | uncapped by Mac | `promptSource`, 15 chars | Agent/source name for the prompt. |
| `promptApproval` | boolean/null | boolean | `promptApproval` | Whether the prompt is an approval request. |
| `promptLabel` | string/null | not currently sent | `promptLabel`, 23 chars | Parser-supported label for future prompt UI. |
| `lastCompletedTool` | string/null | 20 chars | ignored | Last completed tool, used by Mac-side displays. |
| `lastCompletedHint` | string/null | 40 chars | ignored | Last completed hint/summary, used by Mac-side displays. |
| `lastCompletedSource` | string/null | uncapped by Mac | ignored | Agent/source for the last completed task. |
| `lastCompletedDurationMs` | number/null | integer | ignored | Duration of the last completed task in milliseconds. |
| `errorTool` | string/null | extracted from `msg` | ignored | Tool associated with an error state. |
| `errorSource` | string/null | uncapped by Mac | ignored | Agent/source associated with an error state. |
| `activity` | string/null | enum value | `TamaState.activity`, 9 chars | Activity kind: `verify`, `read`, `write`, `shell`, `web`, or `work`. Drives the busy-face verb on the landscape board. |
| `entries` | array<string>/null | max 6 items, 48 chars each | `lines[6][81]`, 80 chars each | Recent activity entries. Parsed for wire compatibility; no transcript UI currently consumes them. |
| `sessions` | array<object>/null | max 6 items | ignored | Multi-session summaries for richer clients. |
| `sessions[].src` | string | uncapped by Mac | ignored | Agent/source name. |
| `sessions[].st` | string | enum value | ignored | Session state: `working`, `idle`, `needsConfirmation`, `errored`, or `thinking`. |
| `sessions[].tool` | string/null | 16 chars | ignored | Current tool for that session. |
| `sessions[].lbl` | string/null | 16 chars | ignored | Human-readable session label. |

## Host-To-Device Commands

These are newline-delimited JSON commands sent over USB or BLE RX.

| Command | Fields | Device reply | Meaning |
| --- | --- | --- | --- |
| `{"time":[epoch,tzOffset]}` | `epoch` seconds, `tzOffset` seconds | none | Set the RTC to local time. |
| `{"cmd":"name","name":...}` | `name` string | `{"ack":"name","ok":bool,"n":0}` | Store the buddy name. |
| `{"cmd":"owner","name":...}` | `name` string | `{"ack":"owner","ok":bool,"n":0}` | Store the owner name. |
| `{"cmd":"species","idx":...}` | `idx` number or `0xFF` | `{"ack":"species","ok":true,"n":0}` | Select ASCII species or installed GIF sentinel for transfer compatibility. |
| `{"cmd":"unpair"}` | none | `{"ack":"unpair","ok":true,"n":0}` | Clear BLE bonds. |
| `{"cmd":"status"}` | none | `{"ack":"status","ok":true,"n":0,"data":...}` | Return name, owner, security, firmware, battery, system, and stats snapshot. |
| `{"cmd":"char_begin",...}` | `name`, `total` | `{"ack":"char_begin","ok":bool,"n":...}` | Begin character asset transfer. |
| `{"cmd":"file",...}` | `path`, `size` | `{"ack":"file","ok":bool,"n":0}` | Open one character file for writing. |
| `{"cmd":"chunk","d":...}` | base64 data | `{"ack":"chunk","ok":bool,"n":bytesWritten}` | Append decoded bytes to the current character file. |
| `{"cmd":"file_end"}` | none | `{"ack":"file_end","ok":bool,"n":bytesWritten}` | Close and validate the current character file size. |
| `{"cmd":"char_end"}` | none | `{"ack":"char_end","ok":bool,"n":0}` | Finish character transfer and reload assets. |
| `{"cmd":"ota_begin",...}` | `size`, `sha256`, `version` | `{"ack":"ota_begin","ok":bool,"n":...,"error":...?}` | Begin firmware OTA to the next OTA partition. |
| `{"cmd":"ota_chunk",...}` | `seq`, base64 `d` | `{"ack":"ota_chunk","ok":bool,"n":bytesWritten,"error":...?}` | Write one OTA chunk. |
| `{"cmd":"ota_end","sha256":...}` | `sha256` | `{"ack":"ota_end","ok":bool,"n":bytesWritten,"error":...?}` | Verify, commit, and reboot into the new firmware. |

## Device-To-Host Messages

| Message | Fields | Meaning |
| --- | --- | --- |
| Permission decision | `{"cmd":"permission","id":promptId,"decision":"allow"|"deny"}` | Sent when physical/debug approval buttons answer an armed prompt. |
| Species adoption | `{"cmd":"species","name":speciesName}` | Sent when the on-device menu adopts a character. The desktop mirrors it into its species preference so heartbeats stop overriding the device's choice. |
| Ack | `{"ack":name,"ok":bool,"n":number,"error":...?}` | Reply for status, character transfer, and OTA commands. `error` is present on some failures. |

## USB Serial Debug Commands

These are plain text commands accepted on USB serial. They intentionally remain
available for hardware-in-the-loop tests.

| Command | Reply / effect |
| --- | --- |
| `ping` | Prints `<<PONG {"fw":...,"git":...,"up":...,"heap":...,"heapMin":...,"heapBig":...,"reset":...,"panics":...,"early":...,"safe":...}>>`. `heapMin`/`heapBig` are the free-heap low-water mark and largest free block; `reset` is the last reset reason; `panics` is the lifetime abnormal-reset count; `early` counts consecutive crashes before stable uptime; `safe` is the current safe-mode tier (0 normal, 1 no character assets, 2 no BLE). |
| `state` | Prints `<<STATE {...}>>` with current parser, display, BLE, and prompt state. Includes `muted`, `screenOff`, numeric `brightness`, the crash-telemetry fields (`reset`, `panics`, `earlyCrashes`, `safeTier`), and `bleDrops` (bytes dropped from the BLE RX ring — nonzero means an inbound line was truncated) for HIL assertions. |
| `reboot` | Prints `<<REBOOT ok>>`, flushes, and restarts. |
| `screenshot` | Prints `<<SCR_BEGIN ...>>`, base64 RGB565 LCD data, then `<<SCR_END LEN=... CRC32=...>>`. |
| `press a [ms]` / `press b [ms]` | Synthesizes GPIO-level button down/up edges and prints `<<PRESS ...>>` markers. |
| `btn a` / `btn b` | Sends an approval/denial for the current prompt without GPIO edge simulation. |
| `mockprompt` | Arms a fake `DEBUG` approval prompt for offline button-path testing. |
| `clearbonds` | Erases all stored BLE bonds (recovery from stale host pairing state). Prints `<<CLEARBONDS ok>>`. |
| `guardclear` | Resets crash-loop bookkeeping (HIL tests use this after deliberate watchdog resets). Prints `<<GUARDCLEAR {"ok":true}>>`. |
| `hang` | Debug: wedges `loop()` so tests can prove the task watchdog reboots a hung device (~30s). |
