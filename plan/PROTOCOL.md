# Boop: protocol

Updated 2026-09-27. Every message between the Boop Mac app and the device,
over Bluetooth or USB.

## 1. The idea

There are four messages: `state` and `moment` from the Mac, and `status`
and `input` from the device. The shape comes from Anthropic's
claude-desktop-buddy protocol, newline-delimited JSON over the Nordic UART
Service (NUS), without its approvals or Claude Desktop compatibility. NUS
is the de facto serial port over BLE, so off-the-shelf tools such as nRF
Connect and Python's `bleak` can talk to the device.

- **Snapshots, not commands.** The Mac keeps sending the whole picture of
  how things are now. A lost or late message fixes itself on the next one,
  and a reconnect needs no special handling.
- **Moments are fire-and-forget.** A cheer or a mumble plays when it
  arrives. Nothing is acknowledged or retried.
- **Nothing important flows back.** The device only reports taps and
  push-to-talk. Boop never approves anything, so no message from the
  device can affect an agent.

Every message has a type, `t`. Receivers ignore unknown types and fields,
so a new optional field never breaks an older peer.

## 2. Transport

| Item | Choice |
| --- | --- |
| Link | BLE. The device is the peripheral and the Mac app the central |
| Service | Nordic UART Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, with RX `6E400002-…` (Mac → device, written without response) and TX `6E400003-…` (device → Mac, notified) |
| Name | `Boop-XXXX`, where XXXX is the last 4 hex digits of the device's Bluetooth MAC |
| Framing | UTF-8 JSON, one object per line, ending in `\n`. A line can span several packets; the receiver buffers until the newline |
| Size | At most 512 bytes a line; the device drops a longer one whole. Replies to `dbg.*` over USB can be longer ([VERIFICATION.md](VERIFICATION.md) §3) |
| MTU | The device asks for 247 bytes. Each side cuts a line into packets the size the link negotiated |
| Flow control | The Mac writes one packet at a time as CoreBluetooth has room (`canSendWriteWithoutResponse`, then `peripheralIsReady`), so a burst never loses part of a line. A line that has started goes out whole; a newer `state` replaces one still waiting; past 4 KB waiting, the oldest lines not yet started are dropped, since the next `state` catches the device up. The device reads every waiting line, for up to 8 ms, before it draws each frame |
| Security | None in v1: no pairing and no encryption, and the Mac connects to any device advertising as `Boop-*` (§6) |

**Reconnecting.** Either side can vanish without warning: the app gets
killed or rebuilt, and the board reflashed or reset. Neither remembers
anything about the other, so a reconnect is just a fresh connect.

- **Finding the device.** macOS, not the app, owns a Bluetooth connection,
  and can keep one alive after the app that made it is gone. A device
  that's still connected doesn't advertise, so the app first asks macOS
  for a `Boop-*` device it's already connected to and takes that link
  over; otherwise it scans.
- **Ready means subscribed.** A connection is up once the Mac is
  subscribed to TX. An attempt that isn't up within 10 s, or fails on the
  way, is cancelled and tried again.
- **Retry timing.** After a drop or a failed attempt the app looks again
  after 1 s, doubling up to 5 s while attempts keep failing, and back to
  1 s once a connection is up.
- **Reconnect by hand.** The Reconnect button in settings drops the link or
  attempt in progress, resets the retry timing and looks again at once.
  Over USB it drops the bridge connection, which comes back a second later.
- **Services changed.** If macOS reports the UART service changed (a
  reflash with a different GATT table), the app drops the link and
  connects again.
- **The device advertises whenever it isn't connected.** It starts again
  on every disconnect, and checks once a second in case that didn't take.
- **A quiet link is dropped.** The Mac sends `state` regularly (§3), so a
  link that has been silent for 30 s is left over from an app that's
  gone. The device drops it and advertises again, so a restarted
  app can find it even if macOS held on to the old link. Anything that
  connects without sending, such as nRF Connect, is dropped after 30 s
  too.

**USB.** The same messages travel over the USB serial port at 460800 baud
([DEVICE.md](DEVICE.md) §7). The Mac app uses it for development and
tests, because an agent can't launch the app with Bluetooth on. The app
never opens the port itself: `tools/boopctl bridge` owns it and shares it
on a Unix socket ([VERIFICATION.md](VERIFICATION.md) §2). A write to the
bridge waits at most 250 ms; one that can't finish drops the connection,
which comes back a second later, so a stuck bridge can't freeze the app.
Over USB the device also accepts `dbg.*` messages for testing
([VERIFICATION.md](VERIFICATION.md) §3).

## 3. Mac → device

### `state`: the whole picture

The Mac sends a `state` whenever something on it other than `time`
changes, and at least every 10 s.

```json
{"t":"state","v":1,"time":1791986400,"name":"Pip","base":"working","attn":{"agent":"claude","project":"landing","more":0},"busy":2,"idle":1,"wait":1,"quiet":0,"vol":6}
```

| Field | Meaning |
| --- | --- |
| `v` | Protocol version, 1 |
| `time`, `name` | Unix time, and Boop's name cut to 23 bytes. The v1 device reads neither |
| `base` | `asleep`, `idle` or `working` ([BEHAVIORS.md](BEHAVIORS.md) §2) |
| `attn` | Only while something needs you: the oldest waiting session's agent (`claude` or `codex`) and project, and how many more are waiting. The project is at most 23 bytes of UTF-8, because the device keeps it in a 24-byte field; a longer one is cut on a character boundary and ends in `..` within those 23 bytes, so the device shows it was cut |
| `busy`, `idle`, `wait` | Session counts. The strip shows `wait` and `busy`; the v1 device ignores `idle` |
| `quiet` | Minutes of quiet mode left; 0 when it's off |
| `vol` | Volume 0–10; 0 is mute |

A new `attn` (a different agent or project) chirps once
([BEHAVIORS.md](BEHAVIORS.md) §3.2). After 30 s without a `state` the
device shows the no-app look ([BEHAVIORS.md](BEHAVIORS.md) §3.4).

### `moment`: something to play once

```json
{"t":"moment","anim":"cheer","ttl":5}
{"t":"moment","say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120},"ttl":5}
{"t":"moment","ttl":5}
```

| Field | Meaning |
| --- | --- |
| `anim` | Optional: `cheer`, `wiggle` or `listening` ([BEHAVIORS.md](BEHAVIORS.md) §5) |
| `say` | Optional: a mumble as Voice built it ([VOICE.md](VOICE.md) §4). `syl` is the gibberish, words separated by spaces and their syllables by `-`; `word` is the optional real word and `at` its place among the syllables; `tune` is `up`, `down`, `bounce`, `flat` or `lift`; `ms` is milliseconds per syllable |
| `ttl` | Seconds, always 5. The v1 device plays a moment as it arrives and ignores `ttl`; the Mac uses it to drop a brain moment that waited too long ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2) |

An animation from the rules comes alone. A mumble, the brain's or working
chatter, comes with only `say` and plays over whatever face is showing. A
moment can carry both, as `tools/boopctl play cheer --say happy` sends. A
new moment replaces one still playing, and while something needs you
only `listening` plays ([BEHAVIORS.md](BEHAVIORS.md) §1).

**The empty moment,** with neither `anim` nor `say`, ends `listening` and
does nothing else: it never ends a cheer, a wiggle or a mumble. A mumble
ends `listening` too, since it's the reply. When the Mac sends the empty
moment is in [BEHAVIORS.md](BEHAVIORS.md) §3.3.

## 4. Device → Mac

### `status`: on connect and every 60 s

```json
{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.4.0","bat":0,"usb":1}
```

| Field | Meaning |
| --- | --- |
| `id` | The device's permanent ID: `b00p-` and the same 4 hex digits as its advertised name, in lower case. The Mac logs it |
| `fw` | Firmware version, shown in the popover's footer |
| `bat` | Battery voltage in mV; 0 with no battery, as on the v1 board |
| `usb` | 1 on USB power; always, on the v1 board |

The Mac answers every `status` with a `state`. Over Bluetooth the device
sends one when a Mac connects. USB has no connection event, so there it
sends one when a message that isn't `dbg.*` arrives and the Mac's previous
one came over Bluetooth or 30 s or more ago. The 60 s `status` goes on the
link the Mac last spoke on.

### `input`: the person did something

```json
{"t":"input","k":"tap"}
```

| `k` | Meaning |
| --- | --- |
| `tap` | Pressed BOOT, or touched the screen (sent on release) |
| `talk_on`, `talk_off` | Held BOOT for push-to-talk, and let go |

The device has already reacted on screen before it sends this. It sends it
on every live link: Bluetooth while a Mac is connected, and USB while the
Mac has spoken there (any message that isn't `dbg.*`) in the last 30 s. So
a tool's `moment` over USB doesn't take taps and push-to-talk away from
the app on Bluetooth. Input a tool injects (`dbg.press`, `dbg.touch`)
goes back only over USB, so a test run never reaches the app on
Bluetooth, or turns on its mic. The Mac ignores any other `k`.

## 5. Lifecycle

On connect the Mac sends its latest `state` at once, and the device sends a
`status`, which the Mac answers with another `state`. Over Bluetooth the
device's connect-time `status` can go out before the Mac has subscribed to
TX, so the Mac doesn't wait for it. From then on the Mac sends `state` on
every change and regularly (§3), and `moment` when something happens;
the device sends `input` when you touch it and `status` every 60 s. After
30 s without a `state` the device shows it has no app
([BEHAVIORS.md](BEHAVIORS.md) §3.4), and it drops a Bluetooth link that
has been silent that long and advertises again. The
next connect starts from the top.

## 6. Not yet

- **Pairing and encryption:** LE Secure Connections with bonding and
  encrypted characteristics, with a 6-digit code on the device typed into
  macOS's prompt.
- **Tying a body to one Boop** by its `id`.
- **Firmware updates over Bluetooth,** probably ESP-IDF's standard OTA on
  a separate characteristic, into the second app slot
  ([DEVICE.md](DEVICE.md) §5).
- **More than one Mac per device, or more than one device per Mac.**
