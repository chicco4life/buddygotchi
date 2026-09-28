# Boop: protocol

Updated 2026-09-28. Every message between the Boop Mac app and the device,
over Bluetooth or USB, and the debug messages tools send over USB. The
code is the source: `app/BoopKit/DeviceLink/`, `StateSnapshot.swift` and
`DeviceMoment.swift` on the Mac, `firmware/src/app/device.cpp` and
`firmware/src/link/` on the device.

## 1. The idea

Five messages carry Boop: `state` and `moment` from the Mac, `status`,
`input` and `ended` from the device (§3–4). Tools also send `dbg.*`
messages over USB (§5).

- **Snapshots, not commands.** The Mac keeps sending the whole picture of
  how things are now. A lost or late message fixes itself with the next
  one, and a reconnect needs no special handling.
- **Moments play when they arrive.** A reaction, a cheer included, plays at once,
  and nothing is retried. The Mac waits only on the brain's reactions,
  which carry an `id`: the device says when each one ended, and how
  (`ended`, §4), so HISTORY can say whether it was seen.
- **Nothing important flows back.** The device reports taps and how a
  reaction ended. Boop never approves anything, so nothing the device
  sends can affect an agent.

Every message is a JSON object with a type, `t`. Receivers ignore unknown
types and unknown fields, so an optional field can be added without
breaking an older peer.

## 2. Transport

Both links carry the same lines. The device listens on both at once and
answers on the link a message came in on.

| Item | Bluetooth | USB |
| --- | --- | --- |
| Roles | The device is a NimBLE peripheral, the Mac a CoreBluetooth central | The board's CH340 serial port at 460800 baud ([DEVICE.md](DEVICE.md) §7). The app never opens it: `boopctl bridge` owns the port and shares it on a Unix socket ([VERIFICATION.md](VERIFICATION.md) §2) |
| Service | Nordic UART Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`: RX `6E400002-…` (Mac → device, written without response), TX `6E400003-…` (device → Mac, notified) | — |
| Name | `Boop-XXXX`, XXXX the last 4 hex digits of the Bluetooth MAC | — |
| Packets | The device asks for a 247-byte MTU and sends notifications of up to MTU − 3 bytes (20 until it's negotiated). The Mac cuts each line to the write size CoreBluetooth reports | A byte stream |
| Security | None: no pairing, no encryption. The Mac connects to any device advertising as `Boop-*` | Local only |

Nordic UART is the de facto serial port over Bluetooth, so a generic tool
such as nRF Connect can talk to the device.

**Framing.** UTF-8 JSON, one object per line, ending in `\n`. A line can
span packets or reads; the receiver buffers until the newline, drops a
trailing `\r` and skips empty lines.

| Limit | Value |
| --- | --- |
| A line the device takes | 512 bytes. A longer one is dropped whole, on either link and in the simulator |
| A reply the device sends over Bluetooth | 512 bytes; longer ones are dropped. Over USB replies can be longer: `dbg.state` is up to 1.5 KB and `dbg.shot` about 103 KB (§5) |
| The device's receive buffers | 2 KB each for USB and Bluetooth. Bluetooth bytes that don't fit are dropped, and the torn line fails to parse |
| A line the Mac takes | 4 KB, so a screenshot passing through the bridge is dropped |

**Flow on the Mac (Bluetooth).** Lines wait in an outbox and go out one
packet at a time, as CoreBluetooth has room (`canSendWriteWithoutResponse`,
then `peripheralIsReady`), so a burst never loses part of a line. A line
that has started goes out whole. A newer `state` replaces one still
waiting. Past 4 KB waiting, the oldest lines not yet started are dropped,
since the next `state` catches the device up. A line sent while no link is
up is dropped.

**Flow on the device.** Each pass of the main loop reads every waiting
line, for up to 8 ms, then draws one frame ([DEVICE.md](DEVICE.md) §4).
Lines are handled in order, so a reply reflects every message before it.
A `dbg.*` line ends the batch, so a tool's input or clock step lands
between frames exactly as in the simulator. A Bluetooth notification that
finds NimBLE's buffers full is retried every 2 ms, up to 20 times, then
dropped.

### Reconnecting

Either side can vanish without warning: the app gets killed or rebuilt,
the board reflashed or reset. Neither remembers the other, so a reconnect
is just a fresh connect.

The Mac, over Bluetooth:

- **Finding the device.** macOS, not the app, owns a Bluetooth
  connection, and can keep one alive after the app that made it is gone.
  A device that's still connected doesn't advertise, so the app first
  asks macOS for a `Boop-*` device it's already connected to and takes
  that link over; otherwise it scans for the service and connects to the
  first `Boop-*` it finds.
- **Ready means subscribed.** A link is up once the Mac is subscribed to
  TX. An attempt that isn't up within 10 s, or fails on the way (no UART
  service, no RX or TX, no subscription), is cancelled and tried again.
- **Retry timing.** After a drop or a failed attempt it looks again after
  1 s, doubling up to 5 s while attempts keep failing, and back to 1 s
  once a link is up.
- **Reconnect by hand.** Settings' Reconnect drops the link or attempt in
  progress, resets the retry timing and looks again at once.
- **Services changed.** If macOS reports the UART service changed (a
  reflash with a different GATT table), the app drops the link and
  connects again. Bluetooth turning off drops it too.

The device, over Bluetooth:

- **It advertises whenever it isn't connected.** It restarts advertising
  on every disconnect, and checks once a second in case that didn't take.
- **A quiet link is dropped.** The Mac sends a `state` at least every
  10 s (§3), so a link with no bytes from the Mac for 30 s is left over
  from an app that's gone. The device drops it and advertises again, so
  a restarted app can find it even if macOS held on to the old link.
  Anything that connects without sending, such as nRF Connect, is dropped
  after 30 s too.

Over USB:

- **The Mac's side.** The app connects to the bridge's socket, and tries
  again every second while it can't. A write waits at most 250 ms; one
  that can't finish drops the connection, which comes back a second
  later, so a stuck bridge can't freeze the app. Settings' Reconnect drops
  it the same way.
- **The device's side.** USB has no connection event. The device counts
  the Mac as connected when it first speaks there (any message that isn't
  `dbg.*`), and again when it speaks after it last spoke on Bluetooth or
  after 30 s of silence on USB. Each time, it sends a `status` (§4).

## 3. Mac → device

A number the device holds to a range (`vol`, `say.at`, `say.ms`,
`loops`) can be any JSON number: one past either end, however big,
reads as that end, and a fraction as its whole part. Missing, or
anything but a number, reads as the default its row gives.

### `state`: the whole picture

The Mac sends a `state` when the core's snapshot differs from the last one
sent, at once on connect, in answer to every `status`, and the latest one
again once 10 s have passed without one (checked every second). A
real line, from `boopdev replay` of the Codex approval fixture
(`codex/synthetic/approval-asked.jsonl`):

```json
{"t":"state","v":1,"base":"idle","mood":"happy","attn":{"agent":"codex","project":"landing","more":0,"id":1},"busy":0,"vol":6,"variant":1}
```

| Field | Type | The Mac sends | The device reads it as |
| --- | --- | --- | --- |
| `v` | int | Always 1 | Not checked |
| `base` | `asleep`, `idle` or `working` | `working` while any session works, `asleep` with no sessions, otherwise `idle` ([BEHAVIORS.md](BEHAVIORS.md) §2) | The look. Missing or unknown reads as `idle` |
| `mood` | `happy`, `excited`, `proud`, `determined`, `grumpy` or `sad` | Boop's mood ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3) | The set of faces every look and animation is drawn in. It also draws `curious`, whose designs it keeps (`boopctl play --mood curious`), though the Mac never sends it. Missing or unknown reads as `happy` |
| `attn` | object, or absent | Only while something needs you: the oldest waiting session | Its presence alone means "needs you" ([BEHAVIORS.md](BEHAVIORS.md) §3.2). A new one, or one with a different `id`, agent or project, chirps once and stops any moment and line |
| `attn.agent` | `claude` or `codex` | The session's agent | Kept in 11 bytes |
| `attn.project` | string, at most 23 bytes of UTF-8 | The project folder's name, precomposed (NFC) so é is one letter, and cut on a character boundary to end in `..` when longer | Kept in 23 bytes; drawn in the status strip |
| `attn.more` | int ≥ 0 | How many more are waiting | The strip's "+N". Missing reads as 0 |
| `attn.id` | int 1–2147483647 | The number of the request shown. Requests are numbered as they start showing, counting up (back to 1 after 2147483647); when one of several subagents asking in a session is answered, the next one's prompt gets a new number. So a new number is a different request, even with the same agent and project (two worktrees of one repo). Each time the app starts, its numbers start at a random one, as moment ids do (§3 `moment`), so a relaunched app's first request can't share a number with the one the device still shows from the last launch. `boopdev replay` and the tests start from 1 | A change chirps. Missing reads as 0, and then only the agent and project tell requests apart |
| `busy` | int ≥ 0 | Sessions working | The strip's working count. Missing reads as 0 |
| `vol` | int 0–10 | The app's volume, 6 by default; 0 is mute | Clamped to 0–10. Missing reads as 6 |
| `variant` | int ≥ 1 | Which variation of the visual shows: needs you's while `attn` is there, else the base's. The core picks it at random each time the visual changes, never the one that visual showed last ([BEHAVIORS.md](BEHAVIORS.md) §2) | The look's variation. Missing reads as 1, and one past the look's variations is held to its last |

Any `state` also restarts the device's 30 s no-app timer
([BEHAVIORS.md](BEHAVIORS.md) §3.4) and ends a `dbg.pattern` or
`dbg.light` (§5). A `state` with `attn`, or with `vol` 0, stops a line
that's playing ([VOICE.md](VOICE.md) §9). Every `state` fits in 512 bytes,
even with the longest names and counts (`DeviceLinkTests`).

### `moment`: something to play

A real line, from a headless run with the board: a brain reaction held
twice (a forced pass, from a dev line on the hook socket):

```json
{"t":"moment","say":{"syl":"da-to-lon","word":"finally","at":3,"tune":"lift","ms":135},"mood":"proud","loops":2,"id":1710758195}
```

| Field | Type | The Mac sends | The device reads it as |
| --- | --- | --- | --- |
| `anim` | `cheer` or `wiggle`, optional | `cheer` with a brain reaction that cheers ([harness/DECISIONS.md](harness/DECISIONS.md) §5); `cheer` or `wiggle` when the dashboard asks. A tap's wiggle is the device's own ([BEHAVIORS.md](BEHAVIORS.md) §3.3) | The animation ([BEHAVIORS.md](BEHAVIORS.md) §5). An unknown one is ignored |
| `say` | object, optional | A mumble as Voice built it ([VOICE.md](VOICE.md) §4), from the brain's `react` | A line to speak, with the mouth and bubble in time |
| `say.syl` | string | 2–8 gibberish syllables: words separated by spaces, syllables by `-` | Every syllable times the mouth; the sound plays at most 12. A syllable it has no clip for keeps its beat, silent |
| `say.word` | string, optional | One word from the vocabulary ([VOICE.md](VOICE.md) §6) | Shown in the bubble, and spoken if it has the clip |
| `say.at` | int, only with `word` | Where the word goes among the syllables: 0 before the first, the syllable count after the last | Clamped to that range. Missing reads as the end |
| `say.tune` | `up`, `down`, `bounce`, `flat` or `lift` | The feeling's tune ([VOICE.md](VOICE.md) §5) | Missing or unknown reads as `flat` |
| `say.ms` | int | Milliseconds per syllable, 90–180 | Clamped to 60–400. Missing reads as 120 |
| `mood` | one of `state`'s moods, optional | The face of the brain's reaction ([harness/DECISIONS.md](harness/DECISIONS.md) §5). A wiggle never carries one | The expression: while this moment plays, the look (or the cheer) is drawn in this mood's design instead of `state`'s. Missing or unknown is ignored: the state's mood |
| `loops` | int, optional | How many loops of its design a reaction's face holds, as Jev picked ([harness/DECISIONS.md](harness/DECISIONS.md) §5). None on a wiggle | Held to 1–6. Missing reads as 1. With the cheer, how many times its design plays. With a `mood` and no animation, how many loops of the design it's drawn in the face holds (below). A wiggle ignores it |
| `variant` | int ≥ 1, optional | With the cheer: which of its variations plays, picked at random by `react`, never the last one ([harness/DECISIONS.md](harness/DECISIONS.md) §5) | The animation's variation. Missing reads as 1, and one past its variations is held to its last. A face with no animation takes the look's variation (`state`'s `variant`) |
| `id` | int 1–2147483647, optional | Only on a moment it waits on: a brain reaction sent while the device is connected. Each time the app starts, its ids start at a random number and count up (back to 1 after 2147483647), so a moment an earlier launch left playing can't share an id with a new one | Answered with one `ended` carrying this `id` (§4). Missing, or anything but an integer from 1 to 4,294,967,295 (a fraction too): no `ended` |

The rules' moments play at once. A brain mumble waits its turn behind
any line or reaction's face playing (not a wiggle, which it plays
over) until the device's `ended` for the last one, and the Mac drops it
rather than send it more than 5 s late
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2 has the whole rule). The Mac
never sends a moment with neither `anim` nor `say`.

On the device, a moment plays as it arrives. A design's loop is how long
it takes to play once through: `loopMs` in
`faces.h` ([DEVICE.md](DEVICE.md) §6), and the same numbers on the Mac
in `FaceLoops`.

- An animation replaces the moment playing, and stops any line. The
  cheer plays its `loops` of its design, which starts over each time,
  timed by the design of the mood it's drawn in when it starts; a wiggle
  lasts 0.7 s.
- A mumble with no animation plays over whatever face is showing and
  replaces any line playing. With an animation in the same moment, as a
  reaction that cheers sends, its bubble stays up at least as long as
  the animation.
- A `mood` with an animation holds for as long as the animation plays.
  With none, as the brain sends it, it holds for its `loops` of the
  design it's drawn in (the look's), ending on a loop boundary of that design's clock:
  the first loop ends at the clock's next boundary, so it can be short,
  and each further loop adds a whole one. Either way it holds at least
  as long as the mumble and its bubble (syllables, two beats for a word,
  then 1.2 s). Then the face goes back to the state's mood. Both
  switches blink like any change of design. If the look changes
  meanwhile (a `state` moves from working to idle), the
  new look is drawn in the moment's mood until the end worked out when
  it started. A newer moment, a tap or "needs you" ends it with the
  moment. The Mac sends its next brain moment once this one's mumble has
  played, without waiting for the face ([ARCHITECTURE.md](ARCHITECTURE.md)
  §3.2), so a face held for its loops is usually ended that way.
- While `attn` is set, neither plays ([BEHAVIORS.md](BEHAVIORS.md) §1).
  Needs you's own design plays its performance once, then holds its
  pending pose, the frame it starts and ends on.
- At volume 0 the mouth and bubble still play, silently.
- A moment with neither a known `anim` nor any syllables is ignored.
- A moment with an `id` is answered with `ended` once none of it plays
  any more (§4).

## 4. Device → Mac

### `status`: who the device is

```json
{"t":"status","v":1,"id":"b00p-54fe","fw":"1.0.0"}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | int | 1 |
| `id` | string | The device's permanent ID: `b00p-` and the same 4 hex digits as its advertised name, in lower case (`b00p-0000` in the simulator and tests). The Mac logs it, and ignores a `status` without one |
| `fw` | string | The firmware version, from the repo's `VERSION` file (`sim` in the simulator). Shown in the popover's footer |

The device sends one when a Mac connects over Bluetooth, and over USB when
the Mac starts speaking (§2), then again whenever 60 s have passed since
the last, on the link the Mac last spoke on. The Mac answers every
`status` with its latest `state`.

### `input`: the person did something

```json
{"t":"input","k":"tap"}
```

| `k` | Meaning |
| --- | --- |
| `tap` | BOOT pressed, or the screen touched anywhere, however long; sent on release |

The device has already reacted on screen before it sends this. It sends it
on every live link: Bluetooth while a Mac is connected, and USB while the
Mac has spoken there (any message that isn't `dbg.*`) in the last 30 s,
so a tool's `moment` over USB doesn't take taps away from the app on
Bluetooth. Input a tool injects (`dbg.press`, `dbg.touch`) goes back only
over USB, so a test run never reaches the app on Bluetooth. The Mac hands
a tap to the core ([BEHAVIORS.md](BEHAVIORS.md) §3.3) and ignores any other
`k`.

### `ended`: a moment the Mac waits on is over

Real lines, from the board on USB, for reactions the headless app
forced: one that played out, one a tap cut short, and one that arrived
while something needed you:

```json
{"t":"ended","id":558386700,"how":"done"}
{"t":"ended","id":558386701,"how":"cut","why":"tap"}
{"t":"ended","id":558386703,"how":"skipped"}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | int | The moment's `id` (§3) |
| `how` | `done`, `cut` or `skipped` | `done`: its animation and its line with its bubble played to the end. The face it holds after them counts too, but ending that early (below) leaves it `done`: the reaction was seen and heard. `cut`: something stopped its animation or its line early. `skipped`: none of it played: something needed you when it arrived (or it had nothing the device can play, which the Mac never sends) |
| `why` | `tap`, `moment`, `needs_you` or `reset`, only with `cut` | What stopped it first: a tap's wiggle, a newer moment (an animation, or any line, which replaces the line playing), "needs you" starting, or `dbg.reset` |

The device sends one for every moment with an `id`, exactly once, on the
link the moment came in on, when none of it plays any more: the
animation, the line with its bubble, and the face it borrows. It's
immediate for `skipped`, and for a `cut` that leaves nothing playing. A
face held on after the line ends at once when a newer moment, a tap or
"needs you" comes, and the moment is `done`. A newer line doesn't stop an
animation (§3), so a moment whose animation plays on ends with it, `cut`
if the newer line replaced its own line. Muting doesn't stop a moment. A
moment without an `id` gets none. A moment whose `id` the device is
still waiting on can only be from a later launch of the Mac app, which
is rare, since a launch never reuses an id and each starts at a random
one (§3): the old one is forgotten without an `ended` (its launch is
gone), so the new one's `ended` is its own.

The Mac ends the reaction's handle from it
([harness/DECISIONS.md](harness/DECISIONS.md) §5), sends the next brain
moment waiting its turn (if its mumble hadn't already played:
[ARCHITECTURE.md](ARCHITECTURE.md) §3.2), and ignores an `id` it isn't waiting on (one it
gave up on, or an earlier launch's). It gives up on a moment, as failed,
when no `ended` has come by its length plus a grace (§6), so firmware
without `ended` or a lost line still settles it, and on every moment it
waits on when the link drops.

## 5. Debug messages (USB only)

Over USB the device also takes messages whose `t` starts with `dbg.`. Over
Bluetooth it ignores them and doesn't reply. Tools and tests send them
([VERIFICATION.md](VERIFICATION.md) §3–4); the Mac app never does, and
ignores the replies it sees through the bridge. Each gets one reply with
the same `t`; an unknown `dbg.*` gets none.

| Request | What it does | Reply |
| --- | --- | --- |
| `{"t":"dbg.ping"}` | Nothing | The vitals (below) |
| `{"t":"dbg.state"}` | Nothing | The device's own view of itself (below) |
| `{"t":"dbg.shot"}` | Draws the current frame afresh | A header, then the picture (below). About 2.3 s |
| `{"t":"dbg.clock","freeze":T}` | Freezes the device clock at T ms and seeds its randomness from T | `{"t":"dbg.clock","now":T,"frozen":true}` |
| `{"t":"dbg.clock","step":MS}` | Moves the clock on MS ms and leaves it frozen (a running clock freezes first) | The same, with the new `now` |
| `{"t":"dbg.clock","run":true}` | Lets the clock run on from where it is | The same, `frozen` false |
| `{"t":"dbg.press","ms":N}` | Holds BOOT for N ms of device time (100 by default), through the same code as a real press | `{"t":"dbg.press"}` |
| `{"t":"dbg.touch","x":X,"y":Y,"ms":N}` | Touches the screen at (X, Y) for N ms (100 by default) | `{"t":"dbg.touch"}` |
| `{"t":"dbg.pattern"}` | Shows the test pattern ([DEVICE.md](DEVICE.md) §7) until the next `state`. With `"fill":N`, a solid screen of palette index N instead; with `"target":[x,y]`, an amber cross at (x, y) on black. Touches don't tap while it shows | `{"t":"dbg.pattern"}` |
| `{"t":"dbg.light","bl":0-255,"led":"#RRGGBB"}` | Holds the backlight, the LED or both until the next `state` | `{"t":"dbg.light"}` |
| `{"t":"dbg.touchcal"}` | Reads the touch calibration. With `"set":[ax,bx,cx,ay,by,cy]` stores one, and with `"clear":true` forgets it ([DEVICE.md](DEVICE.md) §4) | `{"t":"dbg.touchcal","cal":[…]}`, or `"cal":null` when uncalibrated |
| `{"t":"dbg.reset"}` | Forgets everything the Mac said, the moment, the line, any pattern, light or injected input, and the last input, then freezes the clock at 0 and reseeds. A moment the Mac waits on still gets its `ended`, `cut` by `reset` (§4). Every scenario starts with it | `{"t":"dbg.reset"}` |

A clock a tool froze runs again by itself after 60 s with no `dbg.*`
message, so a tool that dies can't leave the board stopped. If the canvas
or the display fails to start, the board prints
`{"t":"dbg.fatal","why":"canvas or display init failed"}` every 2 s
instead of running.

**`dbg.ping`'s vitals.**

| Field | Meaning |
| --- | --- |
| `fw`, `sha` | The firmware version, and the git commit it was built from (10 hex digits, `-dirty` when `firmware/` had changes) |
| `up` | Milliseconds since boot |
| `heap`, `heap_min` | Free heap now, and the least it has been since boot, in bytes |
| `fps` | Frames drawn in the last second: how often the picture changed, not a speed ([DEVICE.md](DEVICE.md) §6) |
| `draw_us`, `push_us` | How long the last frame took to draw and to push to the screen |
| `link` | `usb`, `ble` or `none`: the link the Mac last spoke on. `dbg.*` doesn't count |
| `ble` | `off` (Bluetooth didn't start), `idle` (neither advertising nor connected, so no Mac can find it), `adv` or `conn` |
| `name` | `Boop-XXXX`; left out in the simulator |
| `voice` | The voice assets' version ([VOICE.md](VOICE.md) §8) |
| `w`, `h` | The screen as drawn: 320 and 240 |

**`dbg.state`'s fields.**

| Field | Meaning |
| --- | --- |
| `screen` | `face`, `needs_you`, `no_app` or `pattern` ([DEVICE.md](DEVICE.md) §4) |
| `base`, `mood`, `variant`, `attn`, `vol` | The last `state` as the device read it (§3): `base` `idle` and `mood` `happy` for a missing or unknown one, `variant` held to the look's variations, `vol` clamped, and `attn` (with its `id`, 0 when none came) null unless something needs you |
| `moment` | `{"anim":…,"left_ms":…}` while an animation plays, otherwise null. A mumble on its own leaves it null |
| `expr` | The mood the face borrows while a moment with `mood` plays (§3), otherwise null |
| `life` | `blink` while Boop blinks, otherwise null |
| `led`, `bl` | The LED's colour as `#RRGGBB`, and the backlight level, 0–255 |
| `audio` | `playing` while the mouth follows a line, and its `syllables`. `out` is what the sound output did: `ready` (the DAC started), `playing`, `lines` finished since boot, and for the last line `syl`, `word` (whether it had one), `plan_ms` (beats × `ms`), `out_ms` (samples rendered), `wall_ms` (the DAC's measured time), `cut` (hushed or replaced) and `errors` (DAC writes that timed out) |
| `sfx` | The last sound cue and when, such as `{"k":"chirp","at":27000}`, or null ([BEHAVIORS.md](BEHAVIORS.md) §4), since tests can't hear |
| `last_input` | The last input: `k` (`tap`, or `touch` when a touch starts), `at`, and `x` and `y` for a touch; null before any |
| `rx` | The `state` and `moment` messages received since boot. The pipeline check times hooks by `rx.state` |
| `clock` | `now` and `frozen` |
| `boot`, `touch`, `amp` | Bring-up readings: whether BOOT is down, the touch panel's `down`, `irq` and `raw` `[x, y, z]`, and whether the amp is on |

**`dbg.shot`'s picture.** The header is
`{"t":"dbg.shot","w":320,"h":240,"bytes":77312,"crc":N}`. The next line is
base64 of 512 bytes of palette (256 RGB565 entries, little-endian) then
76,800 bytes of palette indexes, row by row. `crc` is zlib's CRC-32 of
those 77,312 bytes.

## 6. Lifecycle and timings

On connect the Mac sends its latest `state` at once, and the device sends
a `status`, which the Mac answers with another `state`. Over Bluetooth the
device's connect-time `status` can go out before the Mac has subscribed
to TX, so the Mac doesn't wait for it. From then on the Mac sends `state`
on every change and every 10 s, and `moment` when something happens; the
device sends `input` on a tap, `ended` when a moment the Mac waits on is
over, and `status` every 60 s. When the Mac goes
quiet the device shows the no-app look, and drops a Bluetooth link to
advertise again. The next connect starts from the top.

| Timing | Value | Side |
| --- | --- | --- |
| `state` keepalive | The latest again once 10 s have passed since the last, checked every second | Mac |
| No app | 30 s without a `state` ([BEHAVIORS.md](BEHAVIORS.md) §3.4) | Device |
| A quiet Bluetooth link | Dropped after 30 s with no bytes from the Mac, and again 30 s later if that didn't take | Device |
| USB counts as live | For 30 s after the Mac last spoke there | Device |
| `status` | On connect, then every 60 s | Device |
| Connect attempt | Up (subscribed to TX) within 10 s, or retried | Mac |
| Bluetooth retry | 1 s, doubling to 5 s; back to 1 s once up | Mac |
| Advertising check | Every second while not connected | Device |
| USB write | At most 250 ms; a failed write, or a lost bridge, reconnects after 1 s | Mac |
| Brain moment | Dropped once it has waited 5 s for its turn | Mac |
| A brain moment's `ended` | Given up on once the moment's longest length (its line, or its face's loops of the design showing: the last `state`'s look) plus 3 s (`endGraceMs`) has passed since it was sent (§4). Until then the next brain moment waits for it | Mac |
| Reading lines | Up to 8 ms of lines before each frame | Device |
| A frozen debug clock | Runs again after 60 s with no `dbg.*` | Device |

## 7. Not in v1

No pairing or encryption (planned after the ESP-IDF port), no tying a body to one Boop by its `id`, no
firmware updates over Bluetooth (the second app slot is kept for them,
[DEVICE.md](DEVICE.md) §5), and one Mac per device and one device per Mac.
