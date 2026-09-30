# Boop: protocol

Updated 2026-09-30. What Boop says over LinkKit, between the Boop Mac app
and the device, over Bluetooth or USB, and the debug messages tools send
over USB. The generic protocol (the four messages, the turn, lifecycle,
limits) is [linkkit/SPEC.md](../linkkit/SPEC.md); this file is Boop's
vocabulary on top of it: its `state` keys, its `do` names and their
`args`, its `ev` kinds, its rules for the turn and its own `dbg.*`. The
code is the source: `linkkit/Sources/LinkKit/`, `app/BoopKit/DeviceLink/`,
`StateSnapshot.swift` and `DeviceMoment.swift` on the Mac;
`linkkit/device/` (the kit) and `firmware/src/app/device.cpp` (Boop's app
on it) on the device.

## 1. The idea

Four messages carry Boop (SPEC §1): `state` and `do` from the Mac, `hello`
and `ev` from the device (the Mac's bare `hello` asks for the device's).
Tools also send `dbg.*` over USB (§5).

- **Snapshots, not commands.** The Mac keeps sending the whole picture of
  how things are now (`state`). A lost or late one fixes itself with the
  next, and a reconnect needs no special handling.
- **The device decides when things play.** Everything that plays (a brain
  reaction, a finish, a rule's one-shot, the Mac's `listening`) is a `do`,
  a request with an `id` and a `play` mode. The device plays it now, makes
  it wait its turn, or skips it, and says how each one went (`ended`, §4),
  so HISTORY can say whether it was seen. The Mac never times the
  device's animations or lines.
- **Nothing important flows back.** The device reports taps,
  push-to-talk and how each `do` ended. Boop never approves anything, so
  nothing the device sends can affect an agent.

Every message is a JSON object with a type, `t`, on one line of at most
512 bytes (SPEC §2). Receivers ignore unknown types and fields.

## 2. Transport

Both links carry the same lines. The device listens on both at once and
answers on the link a message came in on (SPEC §8).

| Item | Bluetooth | USB |
| --- | --- | --- |
| Roles | The device is a NimBLE peripheral, the Mac a CoreBluetooth central | The board's CH340 serial port at 460800 baud ([DEVICE.md](DEVICE.md) §7). The app never opens it: `boopctl bridge` owns the port and shares it on a Unix socket ([VERIFICATION.md](VERIFICATION.md) §2) |
| Service | Nordic UART Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`: RX `6E400002-…` (Mac → device, written without response), TX `6E400003-…` (device → Mac, notified) | — |
| Name | `Boop-XXXX`, XXXX the last 4 hex digits of the Bluetooth MAC (the kit's `<Prefix>-XXXX`, Boop's prefix) | — |
| Packets | The device asks for a 247-byte MTU and sends notifications of up to MTU − 3 bytes (20 until it's negotiated). The Mac cuts each line to the write size CoreBluetooth reports | A byte stream |
| Security | None: no pairing, no encryption. The Mac connects to any device advertising as `Boop-*` | Local only |

Nordic UART is the de facto serial port over Bluetooth, so a generic tool
such as nRF Connect can talk to the device.

| Limit | Value |
| --- | --- |
| A line the device takes | 512 bytes (SPEC §9). A longer one is dropped whole, on either link and in the simulator |
| A line the device sends over Bluetooth | 512 bytes; longer ones are dropped. Over USB `dbg.*` replies can be longer: `dbg.state` is up to about 1.2 KB and `dbg.shot` about 103 KB (§5) |
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
- **Bluetooth off or not allowed.** Each change of Bluetooth's state is
  logged (`ble: Bluetooth off`). While it's off, refused at the first
  launch's prompt, or missing, the app can't look for the device, and
  the popover says so and what to do (`BLETransport.trouble`), within a
  second, in place of looking and "Plug it into USB power".

The device, over Bluetooth:

- **It advertises whenever it isn't connected.** It restarts advertising
  on every disconnect, and checks once a second in case that didn't take.
- **A quiet link is dropped.** The Mac sends a `state` at least every
  10 s (§3), so a link with no whole line from the Mac for 30 s is left
  over from an app that's gone (SPEC §5). The device drops it and
  advertises again, so a restarted app can find it even if macOS held on
  to the old link, and tries again every 30 s if the drop didn't take.
  Anything that connects without sending lines, such as nRF Connect, is
  dropped after 30 s too. The device keeps this clock in real time, apart
  from the face's no-app look, which counts from the last `state` on the
  device's own clock ([BEHAVIORS.md](BEHAVIORS.md) §3.4).

Over USB:

- **The Mac's side.** The app connects to the bridge's socket, and tries
  again every second while it can't. A write waits at most 250 ms; one
  that can't finish drops the connection, which comes back a second
  later, so a stuck bridge can't freeze the app. Settings' Reconnect drops
  it the same way.
- **The device's side.** USB has no connection event. The Mac counts as
  there while it has spoken on USB (any line that isn't `dbg.*`) in the
  last 30 s, and its first line after that silence gets a `hello` (§4).
  So does the Mac's own `hello`, which it sends first on every connect:
  a Mac relaunched, or reconnected after a write timed out, within the
  30 s still hears one.

## 3. Mac → device

### `hello`: who are you?

On every connect the Mac first sends `{"t":"hello"}`, which asks for the
device's `hello` (§4, SPEC §3), then its `state`; and it asks again every
10 s while none has come.

### `state`: the whole picture

The Mac sends a `state` when the core's snapshot differs from the last one
sent, at once on connect (after its `hello`), in answer to every `hello`, and the latest one
again once 10 s have passed without one (checked every second). A
real line, from `boopdev replay` of the Codex approval fixture
(`codex/synthetic/approval-asked.jsonl`):

```json
{"t":"state","base":"idle","mood":"calm","attn":{"agent":"codex","project":"landing","more":0,"id":1},"busy":0,"vol":6,"variant":1}
```

And one while Claude runs a command, from the replay of
`claude-code/synthetic/permission.jsonl` before it asks:

```json
{"t":"state","base":"working","act":"terminal","mood":"calm","busy":1,"vol":6,"variant":3}
```

A number the device holds to a range (`vol`, and `do`'s `loops`) can be
any JSON number: one past either end, however big, reads as that end, and
a fraction as its whole part. Missing, or anything but a number, reads as
the default its row gives.

| Field | Type | The Mac sends | The device reads it as |
| --- | --- | --- | --- |
| `base` | `asleep`, `idle` or `working` | `working` while any session works, `asleep` with no sessions, otherwise `idle` ([BEHAVIORS.md](BEHAVIORS.md) §2) | The look. Missing or unknown reads as `idle` |
| `act` | `testing`, `delegating`, `terminal`, `searching`, `analyzing`, `tool_use`, `waiting` or `planning`, or absent | Only while `base` is `working` and there's no `attn`: what the agents are doing, by the core's rules, held at least 1.5 s ([BEHAVIORS.md](BEHAVIORS.md) §2) | The look while `base` is `working`: that state's design, in the mood, in working's place, its variations taking turns as working's do. Missing or unknown reads as none: working's. Ignored with `attn`, or when `base` isn't `working` |
| `mood` | `happy`, `excited`, `proud`, `curious`, `determined`, `grumpy`, `sad`, `calm`, `engaged`, `annoyed`, `irritated`, `whiny` or `wounded` | Boop's mood ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3), `calm` until the brain moves it | The set of faces every look and animation is drawn in: it draws all 13 (`render::Mood`, in this order; `boopctl play --mood` any of them). Missing or unknown reads as `happy` |
| `attn` | object, or absent | Only while something needs you: the oldest waiting session | Its presence alone means "needs you" ([BEHAVIORS.md](BEHAVIORS.md) §3.2). A new one, or one with a different `id`, agent or project, plays needs you's performance from its start, the alert with its ding, once, and cuts what plays (below, `do`) |
| `attn.agent` | `claude` or `codex` | The session's agent | Kept in 11 bytes |
| `attn.project` | string, at most 47 bytes of UTF-8 | The project folder's name, precomposed (NFC) so é is one letter, control characters sent as spaces, and cut on a character boundary to end in `..` when longer | Kept in 47 bytes; drawn on the needs-you sign ([DEVICE.md](DEVICE.md) §6) |
| `attn.name` | string, at most 47 bytes of UTF-8, or absent | The thread's name as the agent's app shows it ([ADAPTERS.md](ADAPTERS.md) §2), the last one an event of the session brought; precomposed and cut as `project` is. Absent when there's none | Kept in 47 bytes; drawn on the sign in the project's place. Missing reads as `""`, and then the project shows. Not part of what makes a request new |
| `attn.more` | int ≥ 0 | How many more are waiting | The sign's "+N more". Missing reads as 0 |
| `attn.id` | int 1–2147483647 | The number of the request shown. Requests are numbered as they start showing, counting up (back to 1 after 2147483647); when one of several subagents asking in a session is answered, the next one's prompt gets a new number. So a new number is a different request, even with the same agent and project (two worktrees of one repo). Each time the app starts, its numbers start at a random one, as `do` ids do (below), so a relaunched app's first request can't share a number with the one the device still shows from the last launch. `boopdev replay` and the tests start from 1 | A change alerts again. Missing reads as 0, and then only the agent and project tell requests apart |
| `busy` | int ≥ 0 | Sessions working | The strip's working count. Missing reads as 0 |
| `vol` | int 0–10 | The app's volume, 6 by default; 0 is mute | Clamped to 0–10. Missing reads as 6 |
| `variant` | int ≥ 1 | Which variation of the visual shows: needs you's while `attn` is there, else the look's (`act`'s, else the base's). The core picks it at random each time the visual changes, never the one that visual showed last, and again when a new mood has fewer of the visual than the one showing ([BEHAVIORS.md](BEHAVIORS.md) §2) | The look's first variation (the act's, while there's one): then idle, working, what the agents are doing and asleep take turns between their variations at loop ends (BEHAVIORS.md §2, Taking turns). The same `variant` again leaves the turns alone; another starts them over from it. Missing reads as 1, and one past the look's variations in `mood` (each mood has its own, [DEVICE.md](DEVICE.md) §6) is held to its last |

Any `state` also restarts the device's 30 s no-app timer
([BEHAVIORS.md](BEHAVIORS.md) §3.4) and ends a `dbg.pattern` or
`dbg.light` (§5). A `state` with `attn`, or with `vol` 0, stops a line
that's playing ([VOICE.md](VOICE.md) §9). Every `state` fits in 512 bytes,
even with the longest names and counts (`DeviceLinkTests`).

### `do`: something to play

Everything that plays on Boop's screen at the Mac's word is a `do`
(SPEC §3): its `name` is what plays, `args` carries today's details, and
`play` says how it takes the turn. Real lines, from the simulator: a
brain reaction with its line, a rule's one-shot, and the brain's finish:

```json
{"t":"do","id":558386700,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"previous.finish"},"mood":"proud","loops":1}}
{"t":"do","id":558386701,"name":"starting","play":"if_free","args":{"variant":3,"ctx":"new_task"}}
{"t":"do","id":558386703,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","variant":2,"who":{"agent":"claude","thread":"api"},"say":{"take":"new.d02"},"mood":"proud"}}
```

Every `do` from the Mac has an `id`: each launch starts at a random one and
counts up (back to 1 after 2147483647), so a call an earlier launch left
on the device can't share an id with a new one. It gets exactly one
`ended` (§4). A `do` without one (typed by hand) plays unanswered. A name
the device doesn't have is `skipped`, `unknown`.

#### The names

| `name` | What | `args` | `play` the Mac sends |
| --- | --- | --- | --- |
| `react` | A brain reaction with no animation: a line, a face, or both | `say`, `mood`, `loops` | `next`, `ttl` 5000 |
| `task_complete` | The brain's finish for a turn | `outcome`, `variant`, `who`, `say`, `mood`, `loops` | `next`, `ttl` 5000 |
| `reply_ready` | The brain's finish for a reply | `variant`, `who`, `say`, `mood`, `loops` | `next`, `ttl` 5000 |
| `starting` | A rule's one-shot ([BEHAVIORS.md](BEHAVIORS.md) §3.1) | `variant`, `ctx` | `if_free` |
| `stopped`, `error`, `helper_return` | The rules' other one-shots | `variant` | `if_free` |
| `listening` | The Mac's Talk button: its own mic turns on | `variant` | `now` |
| `stop_listening` | Push-to-talk ended with no reply | — | `if_free` |
| `poked`, `tap_spam` | A tap's poke; only tools send these (`boopctl play`), since a tap's own poke is the device's | `variant`, `loops` | `now` |

Tools (`boopctl play`, the scenarios) send `play` `now`, so each call
replaces the last at once.

| `args` field | Type | The Mac sends | The device reads it as |
| --- | --- | --- | --- |
| `say` | object | The line: `{"take":ID}` or `{"take":ID,"then":ID}`, one or two recorded takes Voice picked, the feeling's then the topic's ([VOICE.md](VOICE.md) §4), from the brain's `react`; `{}` for a reply with no line. Only while the device's `hello` names the Mac's voice pack (§4) | A line to speak: the takes play whole from the card's voice pack, 180 ms apart, with the mouth and bubble in time (below). `{}`, or a `take` the pack doesn't have (or no card), is still a `say` (the reply `listening` waits for) but plays nothing; a `then` it doesn't have leaves the first alone. Any other field in it is ignored |
| `say.take`, `say.then` | string | A take's id, as `voicegen` wrote it into the Mac's `Takes.swift` and the voice pack (`previous.pfft`, `phase1.word.test.test__annoyed__contained`) | The take by that id: its sound, its text in the bubble and its mouth ([DEVICE.md](DEVICE.md) §4) |
| `mood` | one of `state`'s 13 moods | The face of the brain's reaction ([harness/DECISIONS.md](harness/DECISIONS.md) §5), any of the 13 whatever Boop's own mood | The expression: while this call plays, the look (or the animation playing) is drawn in this mood's design instead of `state`'s. Missing or unknown is ignored: the state's mood |
| `loops` | int | How many loops of its design a reaction's face holds, as Jev picked ([harness/DECISIONS.md](harness/DECISIONS.md) §5) | Held to 1–6. Missing reads as 1. With an animation (but `listening`), how many times its design plays. With a `mood` and no animation, how many loops of the design it's drawn in the face holds (below) |
| `variant` | int ≥ 1 | With a finish: which of its variations plays, picked at random by `react` among those for its `outcome`, never the last one ([harness/DECISIONS.md](harness/DECISIONS.md) §5). With a rule's one-shot: the core's pick, at random among the mood's variations of it (for `starting`, those for its `ctx`), never the one it played last | The animation's variation, in the mood it's drawn in, when it's one of those for the call's facts (`outcome`, `ctx`; `render::fitting`). Missing, out of range, or for another outcome or context: the device picks one of those at random, never the one of that design it showed last. It picks as the call takes the turn |
| `outcome` | `success` or `failure`, only with `task_complete` | How the brain judged the turn's finish, from the turn-end text ([harness/DECISIONS.md](harness/DECISIONS.md) §5) | Which of task_complete's variations fit: those for that result. Missing or unknown: any |
| `ctx` | `new_task`, `session` or `continuation`, only with `starting` | What started: a prompt, a session started or cleared, or one resumed or compacted ([BEHAVIORS.md](BEHAVIORS.md) §3.1) | Which of starting's variations fit: those for that context. Missing or unknown: any |
| `who` | object | With a finish for a thread's turn: whose it is | While the finish plays, the strip names them after a mark for its result: a tick for a success, a cross for a failure, three dots for a reply ([BEHAVIORS.md](BEHAVIORS.md) §5), and a tap only dips the face and names the finish's `id` (§4). Ignored with any other name |
| `who.agent` | `claude` or `codex` | The thread's agent | Kept in 11 bytes |
| `who.thread` | string, at most 23 bytes of UTF-8 | The thread's name: as its agent's app shows it once an event brought one (`attn.name`'s), else its workspace (a linked worktree's folder, else the branch), else its project, cut as `attn.project` is | Kept in 23 bytes |

#### The turn: Boop's rules

LinkKit decides when a call plays (SPEC §4): one holds the turn, busy or
resting, and up to 4 `next` calls wait behind it. Boop's app says when a
holder rests, what it refuses and what it cuts (`firmware/src/app/device.cpp`):

- **Rest.** A `react` rests half a second after its line and bubble have
  played (the take, then 1.2 s, from the line's start, then 0.5 s:
  `Device::kReactGapMs`, the pause the Mac used to leave before the next
  reaction or a rule's one-shot), or 1.7 s after it starts when it has
  no line; its face may hold on, resting, for its `loops`, then it ends
  `done`. One with nothing left to play ends `done` sooner, and the next
  call starts then. `task_complete` and `reply_ready` never rest: they
  end when the animation, the line and the bubble are over. The
  one-shots, `poked` and `tap_spam` rest from their start, and so does
  `listening` (the reply takes over), which ends when listening ends.
  `stop_listening` ends `done` as it starts, after ending listening.
- **Refuse** (asked as a call is about to take the turn; the reason is the
  `skipped` `why`): `no_app` while the no-app look shows; `listening`
  while listening holds the face and the call isn't a reply (a `say`, or
  `stop_listening`); `needs_you` while something needs you (`listening`
  itself plays on regardless); `not_listening` for `stop_listening` with
  nothing to stop; `nothing` for a call none of which would play (a `say`
  with no take and no `mood`). A reply ends listening first, even when it
  is then refused.
- **Cut.** A tap's poke that replaces the holder's animation cuts it
  (`why` `tap`), as does BOOT's push-to-talk. A new request in
  `state.attn` cuts the holder's animation and line (`needs_you`;
  `listening` excepted). Either way the call ends once nothing of it
  plays: its line plays on over a poke, and then it ends `cut`.
- **Drop the line.** Push-to-talk ends the calls waiting (`skipped`,
  `mic_on`), since a reaction would end listening, but only those of
  a Mac that hears it: BOOT's drops every call waiting, a tool's
  `dbg.press` only those from USB (where its `talk_on` goes, §4), and the
  Mac's `listening` only those from its own link.

So the brain's reactions wait for the line before them, and the next
starts the millisecond it rests or ends, replacing a face held on after it
(which is then `done`); a rule's one-shot never cuts a brain line
(`if_free` is `busy` then) but may replace a face held after one; a finish
holds the turn to its end. A reaction that has waited longer than its 5 s
is `late`. The Mac sends each call as its turn comes on the Mac's side:
the device times all of it.

#### How a call plays

Boop's app plays a call over whatever plays, in layers, as the moments
before LinkKit did. A design's loop is how long it takes to play once
through: `loopMs` in `faces.h` ([DEVICE.md](DEVICE.md) §6), and the same
numbers on the Mac in `FaceLoops`.

- An animation replaces the animation playing, and stops any line. It
  plays its `loops` of its design, which starts over each time, timed by
  the design of the mood it's drawn in when it starts, then the look
  comes back; a tap's poke plays once. A finish with `who` names them in
  the strip for as long as it plays.
- A line with no animation plays over whatever face is showing and
  replaces any line playing, at once. It speaks for its takes' length
  (each take's samples at 11.025 kHz, in ms rounded down, as the Mac's
  `Take.ms`, and 180 ms between two), and its bubble stays 1.2 s more.
  With an animation in the same call, as the brain's finish sends, its
  line starts at the design's voice window ([VOICE.md](VOICE.md) §9), and
  the animation holds on, resting on its last frame, until the line and
  its bubble end.
- A `mood` with an animation holds for as long as the animation plays.
  With none, as the brain sends it, it holds for its `loops` of the
  design it's drawn in (the look's), ending on a loop boundary of that
  design's clock: the first loop ends at the clock's next boundary, so it
  can be short, and each further loop adds a whole one. Either way it
  holds at least as long as the line and its bubble. A face on its own
  (a `mood`, no line) plays just the same; a line playing plays on under
  it. Then the face goes back to the state's mood. Both switches blink
  like any change of design. If the look changes meanwhile, the new look
  is drawn in the call's mood until the end worked out when it started.
  A newer call or "needs you" ends it; a tap's poke plays under it, in
  its mood ([BEHAVIORS.md](BEHAVIORS.md) §3.3). Over a rule's one-shot
  or a poke, it draws that design in its mood, on the design's clock,
  without cutting it.
- While `attn` is set, none of it plays, except `listening`
  ([BEHAVIORS.md](BEHAVIORS.md) §1). Needs you's own design plays its
  performance once, then holds its pending pose.
- While `listening` plays, a call with a `say`, or `stop_listening`, ends
  it first, then plays as it would have. Anything else is refused, and
  another `listening` keeps the same face, its time topped up
  ([DEVICE.md](DEVICE.md) §4).
- With no app ([BEHAVIORS.md](BEHAVIORS.md) §3.4), nothing but
  `listening` plays: no app shows over everything.
- At volume 0 the mouth and bubble still play, silently.
- A rule's one-shot plays its state's design once through, in the
  state's mood, then the look comes back. A line that comes during it
  plays over it without cutting it, with its `mood` drawn on the
  one-shot's design.
- What shows, first first: no app, `listening`, needs you, a tap's poke
  and the calls, then the look ([BEHAVIORS.md](BEHAVIORS.md) §1).

## 4. Device → Mac

### `hello`: who the device is

The device sends it in answer to the Mac's `hello` (§3), and to the Mac's
first line on a link (for Bluetooth, its first since connecting; for USB,
its first after 30 s of silence), once when that line is the `hello`;
again 60 s after the last one on the link the Mac last spoke on; and when
something in it changes: a new voice pack copied onto the card
(`dbg.card`, §5). The Mac answers every `hello` with its latest `state`
(SPEC §5). A real line, from the simulator:

```json
{"t":"hello","kit":1,"app":"boop","id":"b00p-0000","fw":"sim","does":["react","task_complete","reply_ready","starting","stopped","error","helper_return","listening","stop_listening","poked","tap_spam"],"voice":"1aace295d219"}
```

| Field | Meaning |
| --- | --- |
| `kit`, `app` | LinkKit's version, 1, and `boop` (SPEC §3). The Mac drives only an `app` of `boop` with a `kit` it knows |
| `id` | The device's permanent ID: `b00p-` and the same 4 hex digits as its advertised name, in lower case (`b00p-0000` in the simulator and tests). The Mac logs it |
| `fw` | The firmware version, from the repo's `VERSION` file (`sim` in the simulator). Shown in the popover's footer |
| `does` | Boop's `do` names (§3), in this order |
| `voice` | Boop's own field: the version of the voice pack on its microSD card ([VOICE.md](VOICE.md) §8), `none` with no card or no pack. The Mac sends takes only while it's its own `Take.packVersion`, and logs when they differ |

Firmware from before LinkKit sent `status` instead, and a Mac that meets
it says the firmware is too old (SPEC §6).

### `ev`: what happened

The device sends Boop's `ev` kinds on every live link (SPEC §5): Bluetooth
while a Mac is connected, and USB while the Mac has spoken there in the
last 30 s, so a tool's `do` over USB doesn't take taps and push-to-talk
away from the app on Bluetooth. Input a tool injects (`dbg.press`,
`dbg.touch`) goes back only over USB, so a test run never reaches the app
on Bluetooth, or turns on its mic. `ended` goes back on the link its `do`
came in on. Real lines, from the simulator:

```json
{"t":"ev","kind":"tap","did":"poked"}
{"t":"ev","kind":"tap","did":"dip","data":{"on":558386703}}
{"t":"ev","kind":"ended","data":{"id":558386700,"how":"done"}}
{"t":"ev","kind":"ended","data":{"id":558386701,"how":"skipped","why":"busy"}}
```

| `kind` | `did` | `data` | Meaning |
| --- | --- | --- | --- |
| `tap` | `poked`, `tap_spam`, or `dip` when it only dipped the face | `{"on":ID}` while a brain finish with `who` plays: its `id`, whose thread the Mac opens ([BEHAVIORS.md](BEHAVIORS.md) §3.3) | BOOT pressed for less than 400 ms, or the screen touched anywhere, however long; sent on release |
| `talk_on` | `listening` | — | BOOT held for 400 ms: push-to-talk starts, sent at 400 ms |
| `talk_off` | — | — | BOOT let go after `talk_on`, or held 30 s past it (the device's cap) |
| `ended` | — | `{"id":N,"how":H,"why":W}` | A `do` is over (below) |

The device has already reacted on screen before it sends a tap or
`talk_on`: the poke (or the press dip, while the face is held or a finish
with `who` plays), or `listening` from `talk_on` until the reply
([DEVICE.md](DEVICE.md) §4). The Mac records a tap as a `poke` event, with
`input` as its `specific_type`, and hands it to the core, with the thread
of the finish `on` names while the Mac still waits on that call
([BEHAVIORS.md](BEHAVIORS.md) §3.3, [harness/EVENTS.md](harness/EVENTS.md)
§2); `talk_on` and `talk_off` turn its mic on and off. It ignores any
other `kind`.

**`ended`.** Exactly one for every `do` with an `id` (SPEC §4):

| `how` | `why` | When |
| --- | --- | --- |
| `done` | — | Nothing of it plays any more: its animation, its line with its bubble, and the face it holds after them. Ending that face early (a newer call replacing it while it rests) leaves it `done`: the reaction was seen and heard |
| `cut` | `now` | A `now` call took the turn while it was busy |
| `cut` | `tap` | A tap's poke, or push-to-talk's `listening`, replaced its animation or line; sent once nothing of it plays (its line plays on over a poke) |
| `cut` | `needs_you` | "Needs you" started and stopped its animation or its line |
| `cut` | `reset` | A tool sent `dbg.reset` |
| `skipped` | `needs_you`, `no_app`, `listening`, `not_listening`, `nothing` | Boop refused it (§3) |
| `skipped` | `late`, `busy`, `full`, `unknown`, `reset` | The kit's (SPEC §4): waited past its `ttl`; `if_free` while the turn was busy; a fifth waiting; a name Boop doesn't have; `dbg.reset` while it waited |
| `skipped` | `mic_on` | Push-to-talk, BOOT's or the Mac's `listening`, dropped it while it waited (§3) |

Muting doesn't stop a call. A `do` whose `id` the device still holds or
keeps waiting can only be from a later launch of the Mac app: the old one
is forgotten without an `ended`, so the new one's `ended` is its own.

The Mac ends the reaction's handle from it
([harness/DECISIONS.md](harness/DECISIONS.md) §5) and ignores an `id` it
isn't waiting on (one it gave up on, or an earlier launch's). It gives up
on a call, as failed, when no `ended` has come by its `ttl` plus 60 s
(SPEC §5), so a lost line still settles it, and on every call it waits on
when the link drops.

## 5. Debug messages (USB only)

Over USB the device also takes messages whose `t` starts with `dbg.`. Over
Bluetooth it ignores them and doesn't reply. Tools and tests send them
([VERIFICATION.md](VERIFICATION.md) §3–4); the Mac app never does, and
ignores the replies it sees through the bridge. Each gets one reply with
the same `t`; an unknown `dbg.*` gets none. LinkKit answers `dbg.ping`,
`dbg.clock`, `dbg.shot`, `dbg.reset` and `dbg.state` (SPEC §7), with
Boop's fields in them; the rest are Boop's.

| Request | What it does | Reply |
| --- | --- | --- |
| `{"t":"dbg.ping"}` | Nothing | The vitals (below) |
| `{"t":"dbg.state"}` | Nothing | The device's own view of itself (below) |
| `{"t":"dbg.shot"}` | Draws the current frame afresh | A header, then the picture (below). About 2.3 s |
| `{"t":"dbg.clock","freeze":T}` | Freezes the device clock at T ms and seeds its randomness from T. A T before now has no history to replay: an animation that began after it is over, and the look's design starts over at T | `{"t":"dbg.clock","now":T,"frozen":true}` |
| `{"t":"dbg.clock","step":MS}` | Moves the clock on MS ms and leaves it frozen (a running clock freezes first) | The same, with the new `now` |
| `{"t":"dbg.clock","run":true}` | Lets the clock run on from where it is | The same, `frozen` false |
| `{"t":"dbg.press","ms":N}` | Holds BOOT for N ms of device time (100 by default), through the same code as a real press: 400 ms or more is push-to-talk | `{"t":"dbg.press"}` |
| `{"t":"dbg.touch","x":X,"y":Y,"ms":N}` | Touches the screen at (X, Y) for N ms (100 by default) | `{"t":"dbg.touch"}` |
| `{"t":"dbg.pattern"}` | Shows the test pattern ([DEVICE.md](DEVICE.md) §7) until the next `state`. With `"fill":N`, a solid screen of palette index N instead; with `"target":[x,y]`, an amber cross at (x, y) on black. Touches don't tap while it shows | `{"t":"dbg.pattern"}` |
| `{"t":"dbg.light","bl":0-255}` | Holds the backlight until the next `state` | `{"t":"dbg.light"}` |
| `{"t":"dbg.touchcal"}` | Reads the touch calibration. With `"set":[ax,bx,cx,ay,by,cy]` stores one, and with `"clear":true` forgets it ([DEVICE.md](DEVICE.md) §4) | `{"t":"dbg.touchcal","cal":[…]}`, or `"cal":null` when uncalibrated |
| `{"t":"dbg.card","op":"begin","keep":true}`, then `{"t":"dbg.card","op":"put","at":N,"c":CRC,"d":"<base64>"}`, then `{"t":"dbg.card","op":"end","size":N,"crc":CRC}` | Copies a voice pack onto the card over USB (`boopctl card`, [VOICE.md](VOICE.md) §8). `begin` opens `/boop/voice.tmp`, afresh or, with `keep`, where an earlier copy stopped, and closes the pack, so Boop has no voice while it goes on (`card` `copying`). Each `put` carries up to 360 bytes, appended only when `at` is where the file ends and `c` is their CRC-32. `end` reads the file back, and when its size and CRC-32 match, swaps it in for the pack, reopens it, and sends `hello` again with its `voice`; when they don't, the old pack plays again | `{"t":"dbg.card","op":…,"ok":true,"have":N,"why":""}`, `have` what the file holds; a refused `put` says `why` (`wrong crc`, `not where the card is`, `not base64`, `can't write`). `end`'s reply has `voice`, the pack now playing. With no card, `ok` is false and `why` `no card` |
| `{"t":"dbg.reset"}` | Ends the turn's holder `cut` and every call waiting `skipped`, both `reset` (§4), then forgets everything the Mac said, the animation, the line, any pattern, light or injected input, and the last input, freezes the clock at 0 and reseeds. Every scenario starts with it | `{"t":"dbg.reset"}` |

A clock a tool froze runs again by itself after 60 s with no `dbg.*`
message, so a tool that dies can't leave the board stopped. If the canvas
or the display fails to start, the board prints
`{"t":"dbg.fatal","why":"canvas or display init failed"}` every 2 s
instead of running.

**`dbg.ping`'s vitals.** A real reply, from the simulator:

```json
{"t":"dbg.ping","kit":1,"fw":"sim","up":453787831,"link":"usb","ble":"off","sha":"sim","heap":0,"heap_min":0,"fps":0,"draw_us":0,"push_us":0,"voice":"1aace295d219","card":"ok","fx":"768b38d359b5","w":320,"h":240}
```

| Field | Meaning |
| --- | --- |
| `kit`, `fw` | LinkKit's version and the firmware version |
| `up` | Milliseconds since boot |
| `link` | `usb`, `ble` or `none`: the link the Mac last spoke on. `dbg.*` doesn't count |
| `ble` | `off` (Bluetooth didn't start), `idle` (neither advertising nor connected, so no Mac can find it), `adv` or `conn` |
| `name` | `Boop-XXXX`; left out in the simulator |
| `hello_long` | Only when `hello` doesn't fit in a line: its whole length. It then goes without `voice` (SPEC §3). Boop's is about 260 bytes, so never |
| `sha` | The git commit the firmware was built from (10 hex digits, `-dirty` when `firmware/` had changes) |
| `heap`, `heap_min` | Free heap now, and the least it has been since boot, in bytes |
| `fps` | Frames drawn in the last second: how often the picture changed, not a speed ([DEVICE.md](DEVICE.md) §6) |
| `draw_us`, `push_us` | How long the last frame took to draw and to push to the screen |
| `voice` | The version of the voice pack on the card, as `hello` gives it (§4) |
| `card` | The microSD card: `ok`, `no card`, `no pack`, `copying` or `card failed` ([VOICE.md](VOICE.md) §8); `none` in the tests, and in the simulator whether it found `.build/voice/voice.bin` |
| `fx` | The sound effects' version ([VOICE.md](VOICE.md) §10) |
| `w`, `h` | The screen as drawn: 320 and 240 |

**`dbg.state`'s fields.** Boop's, then LinkKit's `clock`, `rx` and `turn`.
The end of a real reply, from the simulator, with a reaction playing and
the next one waiting its turn:

```json
"clock":{"now":500,"frozen":true},"rx":{"state":1,"do":3},"turn":{"holder":{"id":558386700,"name":"react","resting":false},"waiting":[{"id":558386702,"name":"react","left_ms":4500}]}}
```

| Field | Meaning |
| --- | --- |
| `screen` | `face`, `needs_you`, `no_app` or `pattern` ([DEVICE.md](DEVICE.md) §4) |
| `base`, `act`, `mood`, `variant`, `attn`, `vol` | The last `state` as the device read it (§3): `base` `idle` and `mood` `happy` for a missing or unknown one, `act` null for none or one it doesn't know, `variant` held to the look's variations, `vol` clamped, and `attn` (with its `name`, `""` when none came, and its `id`, 0 when none came) null unless something needs you |
| `look_variant` | The variation of the look showing (the act's, else the base's), from 1: `variant` until the looks take turns ([BEHAVIORS.md](BEHAVIORS.md) §2) |
| `moment` | `{"anim":…,"left_ms":…,"variant":…}` while an animation plays, by its design's name and its variation from 1; otherwise null. A line on its own leaves it null |
| `expr` | The mood the face borrows while a call with `mood` plays (§3), otherwise null |
| `life` | `blink` while Boop blinks, otherwise null |
| `led`, `bl` | The LED's colour as `#RRGGBB`, and the backlight level, 0–255 |
| `audio` | `playing` while the mouth follows a line (its takes' length), and `take`, the id of the line's first take in the bubble, or null while none shows. `out` is what the sound output did: `ready` (the DAC started), `playing` (the amp is on: something sounds, or did in the last second), `lines` finished since boot, and for the last line `take` (its first take's id, or null before any), `plan_ms` (the line's length), `out_ms` (samples rendered), `wall_ms` (the DAC's measured time), `cut` (hushed or replaced) and `errors` (DAC writes that timed out). `fx` is the face's sound effects ([VOICE.md](VOICE.md) §10): `sent` to the sound output since boot, and the `last` one's clip, such as `{"sent":42,"last":"keyB"}`, or null before any |
| `alert` | When needs you's performance last started for a new request shown, in device ms, such as `27000`, or null before any ([BEHAVIORS.md](BEHAVIORS.md) §3.2) |
| `last_input` | The last input: `k` (`tap`, `talk_on`, `talk_off`, or `touch` when a touch starts), `at`, and `x` and `y` for a touch; null before any |
| `boot`, `touch`, `amp` | Bring-up readings: whether BOOT is down, the touch panel's `down`, `irq` and `raw` `[x, y, z]`, and whether the amp is on |
| `clock` | `now` and `frozen` |
| `rx` | The `state` and `do` lines received since boot. The pipeline check times hooks by `rx.state` |
| `turn` | Who holds the turn (`id`, null for a `do` without one, `name`, `resting`), or null, and the calls waiting, oldest first, each with the ms `left` before it's `late` (SPEC §7) |

**`dbg.shot`'s picture.** The header is
`{"t":"dbg.shot","w":320,"h":240,"bytes":77312,"crc":N}`. The next line is
base64 of 512 bytes of palette (256 RGB565 entries, little-endian) then
76,800 bytes of palette indexes, row by row. `crc` is zlib's CRC-32 of
those 77,312 bytes.

## 6. Lifecycle and timings

On connect the Mac sends `hello` and its latest `state` at once; the
device answers with its `hello`, which the Mac answers with another
`state` (SPEC §5). From then on the Mac sends `state` on every change and every
10 s, and a `do` when something should play; the device sends a tap and
push-to-talk as they happen, an `ended` for every `do`, and `hello` every
60 s. When the Mac goes quiet the device shows the no-app look, and drops
a Bluetooth link to advertise again. The next connect starts from the top.

| Timing | Value | Side |
| --- | --- | --- |
| `state` keepalive | The latest again once 10 s have passed since the last, checked every second | Mac |
| No app | 30 s without a `state` ([BEHAVIORS.md](BEHAVIORS.md) §3.4) | Device |
| Push-to-talk | BOOT held 400 ms; `talk_off` by itself 30 s after `talk_on` ([DEVICE.md](DEVICE.md) §4) | Device |
| `listening` | At most 30 s, then 8 s for the reply; `talk_off` cuts that to 8 s from then ([DEVICE.md](DEVICE.md) §4) | Device |
| A reaction's rest | Its line's start plus the take, 1.2 s and 0.5 s; 1.7 s after it starts with no line (§3) | Device |
| A `next` call's wait | Its `ttl`, 5000 ms from the Mac: then `late` | Device |
| A quiet Bluetooth link | Dropped after 30 s with no line from the Mac, and again 30 s later if that didn't take | Device |
| USB counts as live | For 30 s after the Mac last spoke there | Device |
| `hello` | On the Mac's `hello` or its first line on a link, then 60 s after the last | Device |
| Connect attempt | Up (subscribed to TX) within 10 s, or retried | Mac |
| Bluetooth retry | 1 s, doubling to 5 s; back to 1 s once up | Mac |
| Advertising check | Every second while not connected | Device |
| USB write | At most 250 ms; a failed write, or a lost bridge, reconnects after 1 s | Mac |
| A `do`'s `ended` | Given up on once its `ttl` plus 60 s have passed since it was sent (SPEC §5) | Mac |
| Reading lines | Up to 8 ms of lines before each frame | Device |
| A frozen debug clock | Runs again after 60 s with no `dbg.*` | Device |

## 7. Not in v1

No pairing or encryption (planned after the ESP-IDF port), no tying a body to one Boop by its `id`, no
firmware updates over Bluetooth (the second app slot is kept for them,
[DEVICE.md](DEVICE.md) §5), and one Mac per device and one device per Mac.
