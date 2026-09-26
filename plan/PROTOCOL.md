# Boop: protocol

Updated 2026-09-26. Every message between the Boop Mac app and the device,
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
  push-to-talk. Boop never approves
  anything, so no message from the device can affect an agent.

## 2. Transport

| Item | Choice |
| --- | --- |
| Link | BLE. The device is the peripheral and the Mac app is the central |
| Service | Nordic UART Service (`6E400001-…`), with one RX characteristic (Mac → device) and one TX characteristic (device → Mac) |
| Framing | UTF-8 JSON, one object per line, ending in `\n`. A line can span several BLE packets; the receiver buffers until the newline |
| MTU | The device asks for 247 bytes. Each side splits a line into packets of the size the link negotiated |
| Size | ≤ 512 bytes per line. Replies to `dbg.*` over USB can be longer ([VERIFICATION.md](VERIFICATION.md) §3) |
| Security | **v1: none.** No pairing and no encryption for the first test; the Mac app connects to any device advertising as `Boop-XXXX`. **Later:** LE Secure Connections with bonding and encrypted characteristics, with a 6-digit code on the device typed into macOS's prompt |
| Advertised name | `Boop-XXXX`, where XXXX is the last 4 hex digits of the device's MAC |

**Reconnecting.** Either side can vanish without warning: the app gets
killed or rebuilt, and the board gets reflashed or reset. Neither side
remembers anything about the other, so a reconnect is just a fresh connect.

- **Finding the device.** macOS's Bluetooth service, not the app, owns a
  connection, and it can keep one alive after the app that made it is gone.
  A device that's still connected doesn't advertise, so a scan can't see
  it. The app first asks macOS for a `Boop-*` device it's already connected
  to and takes that link over. Otherwise it scans.
- **Ready means subscribed.** A connection counts as up once the Mac is
  subscribed to TX, so lines can flow both ways. An attempt that isn't up
  within 10 s is cancelled and tried again. Any failure along the way
  (connect, service or characteristic lookup, subscribe) does the same.
- **Retry timing.** After a drop or a failed attempt the app looks again
  after 1 s, doubling up to 5 s while attempts keep failing, and back to
  1 s once a connection is up. Scanning is passive, so retrying quickly
  costs nothing.
- **Reconnect by hand.** The settings screen's Reconnect button drops the
  link or attempt in progress, resets the retry timing and looks again at
  once. Over USB it reconnects to the bridge.
- **Services changed.** If macOS reports the UART service changed (a
  reflash with a different GATT table), the app drops the link and
  connects again.
- **The device always advertises when it isn't connected.** It starts
  again on every disconnect (NimBLE-Arduino 2.x doesn't by default), and
  checks once a second in case that didn't take.
- **A quiet link is dropped.** The Mac sends a `state` at least every 10 s,
  so a link that has been silent for 30 s is left over from an app that's
  gone. The device drops it and starts advertising again, so a restarted
  app can find it even if macOS held on to the old link. Anything that
  connects without sending, such as nRF Connect, is dropped after 30 s too.

**USB transport.** The same messages also travel over the USB serial port
at 460800 baud, one JSON object per line. The Mac app uses it for
development and automated tests, because an agent can't launch the app with
Bluetooth on. The app never opens the port itself: it reaches it through
`tools/boopctl bridge`, which owns the port and shares it on a Unix socket
([VERIFICATION.md](VERIFICATION.md) §2). The device treats both links the
same and answers on the link a message came in on. Over USB it also accepts
`dbg.*` messages for testing ([VERIFICATION.md](VERIFICATION.md) §3).

Every message has a type, `t`. Receivers ignore unknown types and fields,
so new optional fields never break an older peer.

## 3. Mac → device

### `state`: the whole picture, on every change and every 10 s

```json
{"t":"state","v":1,"time":1790000000,"name":"Pip",
 "base":"working","attn":{"agent":"codex","project":"landing","more":0},
 "busy":2,"idle":1,"wait":1,"quiet":0,"vol":6}
```

| Field | Meaning |
| --- | --- |
| `v` | Protocol version |
| `time` | Unix time. The v1 device doesn't read it |
| `name` | Boop's name. The v1 device doesn't show it since the stats screen was parked |
| `base` | `asleep`, `idle` or `working` |
| `attn` | Present when something needs you: which agent and project, and how many more are waiting. A new `attn` (different agent or project) chirps once; the same one doesn't chirp again |
| `busy` / `idle` / `wait` | Session counts for the status strip |
| `quiet` | Minutes of quiet left; 0 when not quiet |
| `vol` | Volume 0–10; 0 is mute |

If the device gets no `state` for 30 s, it shows the "no app" face.

### `moment`: something to play once

```json
{"t":"moment","anim":"cheer","say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120},"ttl":5}
```

| Field | Meaning |
| --- | --- |
| `anim` | Optional. An animation from the device's set ([BEHAVIORS.md](BEHAVIORS.md) §5). Without one, the `say` plays over whatever face is showing |
| `say` | Optional mumble, as built by Voice: gibberish syllables (`syl`: syllables within a gibberish word joined with `-`, words separated by spaces), an optional real word and its position (`at`, an index into the syllables), the tune (`up`, `down`, `bounce`, `flat` or `lift`), and milliseconds per syllable. The real word takes two beats |
| `ttl` | Seconds. The v1 device plays a moment as soon as it arrives or skips it, so it doesn't read `ttl`; the field is kept for later |

The device plays moments on top of whatever `state` says, except while
something needs you, when only the moments in [BEHAVIORS.md](BEHAVIORS.md)
§1 play. A new moment replaces one that's still playing.

## 4. Device → Mac

### `status`: on connect and every 60 s

```json
{"t":"status","v":1,"id":"b00p-7f3a","fw":"1.0.0","bat":0,"usb":1}
```

`id` is the device's permanent ID: `b00p-` and the same 4 hex digits as the
advertised name, in lower case. The Mac shows and logs it; tying a body to
one Boop is for later (§6). `bat` is battery voltage in mV, 0 when there's
no battery, as on the v1 board. `usb` is 1 when on USB power (always, on
the v1 board). The Mac answers every `status` with a `state`.

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
| `tap` | Touched the screen or pressed BOOT |
| `talk_on`, `talk_off` | Push-to-talk held and released |

The device has already reacted on screen before sending this. The Mac
ignores any other `k`, such as `focus` or `feel` from a board built before
those were removed.

## 5. Lifecycle

```
connect ─► Mac: state
           device: status ─► Mac: state
                                        │
          running: state on change and every 10 s,
                   moment when something happens,
                   input when you touch it,
                   status every 60 s ─► Mac: state
                                        │
          30 s without a state ─► device: "no app" face; over Bluetooth
                                  it drops the link and advertises
                                  Mac reconnects ─► same as connect
```

On connect the Mac sends a `state` itself. Over Bluetooth, the device's
connect-time `status` can go out before the Mac has subscribed to it, so
the Mac doesn't depend on it.

## 6. Not yet

- **Pairing and encryption** (§2).
- **Firmware updates over Bluetooth**, probably ESP-IDF's standard OTA
  pattern on a separate characteristic.
- **More than one Mac per device, or more than one device per Mac.**
