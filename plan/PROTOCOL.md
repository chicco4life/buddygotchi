# Boop: protocol

Updated 2026-09-25. Every message between the Boop Mac app and the device,
over Bluetooth or USB.

## 1. The idea

There are four message types: two from the Mac and two from the device.

The design borrows from two protocols that already work for this kind of
gadget:

- **Anthropic's claude-desktop-buddy protocol.** Newline-delimited JSON
  over the Nordic UART Service, with a full status snapshot sent on every
  change and every 10 s. We keep that shape and drop what we don't need,
  such as approvals and compatibility with Claude Desktop.
- **The Nordic UART Service (NUS) itself.** It's the de facto "serial port
  over BLE". Firmware libraries, the nRF Connect app and Python's `bleak`
  all speak it, so it's easy to debug with off-the-shelf tools.

Three rules follow from that:

- **Snapshots, not commands.** The Mac regularly sends the whole picture of
  "how things are now". A lost or late message fixes itself on the next
  one, and a reconnect needs no special handling.
- **Moments are fire-and-forget.** A cheer or a mumble either plays in time
  or is skipped. Nothing is acknowledged or retried.
- **Nothing important flows back.** The device only reports taps and
  push-to-talk. Boop never approves anything, so no message from the device
  can affect an agent.

## 2. Transport

| Item | Choice |
| --- | --- |
| Link | BLE. The device is the peripheral and the Mac app is the central |
| Service | Nordic UART Service (`6E400001-…`), with one RX characteristic (Mac → device) and one TX characteristic (device → Mac) |
| Framing | UTF-8 JSON, one object per line, ending in `\n`. A line can span several BLE packets; the receiver buffers until the newline |
| Size | ≤ 512 bytes per line |
| Security | **v1: none.** No pairing and no encryption for the first test; the Mac app connects to any device advertising as `Boop-XXXX`. **Later:** LE Secure Connections with bonding and encrypted characteristics, with a 6-digit code on the device typed into macOS's prompt |
| Advertised name | `Boop-XXXX`, where XXXX is the last 4 hex digits of the device's MAC |

**USB transport.** The same messages also travel over the USB serial port
at 460800 baud, one JSON object per line. The Mac app uses it for
development and automated tests, because an agent can't launch the app with
Bluetooth on. The device treats both links the same and answers on the
link a message came in on. Over USB it also accepts `dbg.*` messages for
testing ([VERIFICATION.md](VERIFICATION.md) §3).

Every message has a type, `t`. Receivers ignore unknown types and fields,
so new optional fields never break an older peer.

## 3. Mac → device

### `state`: the whole picture, on every change and every 10 s

```json
{"t":"state","v":1,"time":1790000000,"name":"Pip",
 "base":"working","attn":{"agent":"codex","project":"landing","more":0},
 "busy":2,"idle":1,"wait":1,
 "mood":{"energy":70,"pace":110,"pitch":120},
 "quiet":0,"focus":false,"vol":6,"night":false,
 "level":12,"prog":40,"days":12,"hungry":0,
 "threads":[["codex","landing","wait"],["claude","jetpack","work"],["codex","buddy","work"]]}
```

| Field | Meaning |
| --- | --- |
| `v` | Protocol version |
| `time` | Unix time; the board has no clock |
| `name` | Boop's name |
| `base` | `asleep`, `idle` or `working` |
| `attn` | Present when something needs you: which agent and project, and how many more are waiting. The device runs the nudge ladder while it's there. A new `attn` (different agent or project) restarts the ladder; the same one continues it |
| `busy` / `idle` / `wait` | Session counts for the status strip |
| `mood` | Energy, pace and pitch, 0–200 with 100 as neutral. They shape how every animation and sound plays |
| `quiet` | Minutes of quiet left; 0 when not quiet |
| `focus` | Focus mode: no sound or buzz, and "needs you" is visual only |
| `vol` | Volume 0–10; 0 is mute |
| `night` | The Mac's view of whether it's night, for dimming and sleepiness |
| `level`, `prog`, `days` | For the stats screen: level, progress to the next level (0–100), days together |
| `hungry` | 0 fed, 1 hungry, 2 starving ([BEHAVIORS.md](BEHAVIORS.md) §4) |
| `threads` | Up to 8 rows for the threads view: agent, project, status |

If the device hears nothing for 30 s, it shows the "no app" face.

### `moment`: something to play once

```json
{"t":"moment","anim":"cheer","size":2,"say":{"syl":"bi do ba na","word":"done","at":4,"tune":"up","ms":120},"ttl":5}
```

| Field | Meaning |
| --- | --- |
| `anim` | An animation from the device's set ([BEHAVIORS.md](BEHAVIORS.md) §7) |
| `size` | 1–3, for small, medium or big |
| `say` | Optional mumble, as built by Voice: gibberish syllables, an optional real word and its position (`at`, an index into the syllables), the tune (`up`, `down`, `bounce`, `flat` or `lift`), and milliseconds per syllable |
| `ttl` | Seconds; the device skips it if it can't start in time |

The device plays moments on top of whatever `state` says. A new moment
replaces one that's still playing.

## 4. Device → Mac

### `status`: on connect and every 60 s

```json
{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1","bat":3910,"usb":1}
```

`id` is the device's permanent ID, which the Mac uses to know which Boop
this body belongs to: `b00p-` and the same 4 hex digits as the advertised
name. `bat` is battery voltage in mV, and `usb` is 1 when on USB power (the
v1 board has no battery, so it's always 1). When the Mac receives the first
`status` after connecting, it replies with a `state`.

USB has no connection event, so over USB the device sends `status` when the
Mac first speaks (any message that isn't `dbg.*`), and again when it speaks
after 30 s of silence. The 60 s `status` goes on the link the Mac last
spoke on.

### `input`: the person did something

```json
{"t":"input","k":"tap"}
```

| `k` | Meaning |
| --- | --- |
| `tap` | Tapped the face or pressed BOOT |
| `talk_on`, `talk_off` | Push-to-talk held and released |
| `focus` | Focus mode toggled on the device; the Mac confirms it in the next `state` |
| `feel` | Touched and held the face. The device already shows a face from its mood; the Mac may reply with a mumble |

The device has already reacted on screen before sending this. Moving
between the face, threads and stats screens is local and sends nothing.

## 5. Lifecycle

```
connect ─► device: status ─► Mac: state
                                        │
          running: state on change and every 10 s,
                   moment when something happens,
                   input when you touch it,
                   status every 60 s
                                        │
          30 s without a state ─► device: "no app" face, keeps advertising
                                  Mac reconnects ─► same as connect
```

## 6. Not yet

- **Pairing and encryption** (§2).
- **Firmware updates over Bluetooth**, probably ESP-IDF's standard OTA
  pattern on a separate characteristic.
- **More than one Mac per device, or more than one device per Mac.**
