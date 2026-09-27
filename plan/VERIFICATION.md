# Boop: verification

Updated 2026-09-27. How we check that Boop works, including what's on its
screen, without a person watching.

## 1. The loop

Every change goes around the same loop and stops at the first level that
fails:

```
 change ─► L0 unit tests ─► L1 simulator ─► flash ─► L2 device over USB ─► L3 webcam ─► commit
            (logic)          (look at the     │       (same pixels as       (the real panel,
                              PNGs)           │        the simulator?)       when authorised)
                                              └─ skip L2–L3 for Mac-only changes
```

L4 and L5 run when a change touches the pipeline or the brain. L6 needs
the owner.

| Level | Question | Needs |
| --- | --- | --- |
| L0 Unit tests | Is the logic right? | Nothing |
| L1 Simulator | Does the renderer draw what we meant? | Nothing: the device's drawing code builds on the Mac |
| L2 Device over USB | Does the board do and draw exactly that? | The board on USB |
| L3 Webcam | Does the real panel look right: colours, orientation, motion? | The board facing the camera, when authorised (§6) |
| L4 Pipeline | Does a real hook event reach the screen? | The board on USB; no Bluetooth |
| L5 Brain | Do the real brains behave? | Apple's on-device model, and Jev's key for Jev |
| L6 Owner | Bluetooth, the mic, touch, sound, real agents, how it feels | The owner |

## 2. The tools

Run a tool with `--help` for its flags: `tools/boopctl` (and
`tools/boopctl <command>`), `app/.build/debug/boopdev`,
`app/.build/debug/Boop`. `Boop` stops with its usage on a flag it doesn't
take, before anything starts, so a typo can't launch the menu-bar app.

| Make target | What it does |
| --- | --- |
| `make build` | Builds the Mac app, `boop-hook` and `boopdev` in one `swift build`, then runs `make sign` |
| `make sign` | Re-signs `Boop` with the "Boop Dev" code-signing certificate (or `SIGN_IDENTITY`) when the login keychain has one, so the Keychain keeps trusting the app across rebuilds and stops asking for the Jev key. Otherwise the build stays ad-hoc signed. The owner makes the certificate once in Keychain Access → Certificate Assistant → Create a Certificate…, type Code Signing |
| `make test` | Swift unit tests, the eval scenarios included, through the XCTest shim (`python3 app/tools/test.py`), since there's no Xcode |
| `make eval` | The harness eval scenarios ([EVALS.md](EVALS.md)); `REAL=1` runs the real brains (L5) |
| `make run` / `make debug` | The Mac app with Bluetooth, for the owner; `debug` adds `--debug` |
| `make fw` / `make flash` | Builds the firmware; `flash` also uploads it over USB (`BOOP_PORT` picks the port) |
| `make fw-test` | Firmware unit tests on the Mac (`pio test -e native`) |
| `make sim` | Every scenario in the simulator, against the goldens (L1) |
| `make e2e` | The pipeline check (L4) |
| `make tools` | `tools/.venv` with pyserial and Pillow. `tools/boopctl` makes it on first run; this refreshes it |
| `make tools-test` | The tools' own tests, with no board or camera: `boopctl`'s command line and the webcam recorder on synthetic video |
| `make clean` | Deletes `app/.build` and `firmware/.pio` |

| `boopctl` command | What it does |
| --- | --- |
| `ping` | Firmware version and SHA, uptime, heap, fps and link (§3) |
| `state` | The device's own view of itself (§3) |
| `shot` | Saves a screenshot of the device's canvas as a PNG |
| `send '<json>'` | Sends one protocol message as the Mac would; a `dbg.` request prints the reply |
| `play <what>` | Makes the board do one thing the Mac can, and checks it took: `cheer`, `wiggle` or `listening` ([BEHAVIORS.md](BEHAVIORS.md) §5), `--say FEELING` adding a mumble; `stop`, the empty moment; `needs`, a fake "needs you" that reports its chirp; `pattern`, the test pattern |
| `mumble [feeling…]` | Plays the Mac's Voice lines for each feeling, without and with a word, and checks each in `audio.out`: syllables, word, and the DAC's time within 10% of beats × `ms`. Then checks that a muted line moves the mouth silently. `--board-volume` and `--levels` are for listening by ear |
| `sim [scenario…]` | Plays scenarios in the simulator and compares them with the goldens (L1); `--accept` copies the pictures in |
| `run [scenario…]` | Plays scenarios on the board and diffs each screenshot against the simulator's, threshold 0 (L2), then lets the clock run again |
| `perf` | Samples fps and heap once a second; `--motion` keeps the face moving (L2) |
| `soak` | Random, realistic traffic and inputs for `--minutes` (L2); `--pipeline` loops the L4 fixtures through the headless app instead |
| `e2e [fixture…]` | The pipeline check (L4) |
| `bridge` | Owns the serial port and shares it on a Unix socket (below) |
| `cam frame\|pattern\|clip <name>` | Webcam helpers (L3); `--camera ID` or `BOOP_CAMERA` picks the camera |
| `calibrate` | Touch calibration: a person taps crosses on the screen (L6). `--show` prints the stored map, `--show --clear` forgets it |

| Other tool | What it does |
| --- | --- |
| `Boop --headless` | The whole runtime with its own state directory, no UI and no Bluetooth (L4). On its hook socket, `{"dev":"advance","ms":N}` moves its clock and `{"dev":"talk","words":…}` hands it what you said |
| `Boop --debug` | Prints every hook, decision, device line and brain pass as it happens ([HARNESS.md](HARNESS.md) §8) |
| `Boop --snapshots DIR` | Renders the popover's panes and the menu-bar icons to PNGs, light and dark, from fixtures, and fails on low contrast (L0). No runtime, Bluetooth or microphone |
| `boopdev eval` | The eval scenarios ([EVALS.md](EVALS.md)); `--real` is L5 |
| `boopdev watch [FILE]` | Prints a `debug.jsonl` readably as it grows; with no file, the everyday app's |
| `boopdev replay <fixture>` | Runs recorded hook payloads through the hook's field picking, the adapter and the core on a virtual clock, printing every decision; with `--socket`, through the real `boop-hook` to a running app |
| `boopdev voice <feeling> [word]` | Prints the Minion lines `react` would build |
| `boopdev talk "<words>" --socket PATH` | Hands a push-to-talk transcript to a running headless app |
| `boopdev hooks status\|install\|remove --home DIR` | The hook installer, against any HOME |
| `skills/doctor/doctor.sh` | Checks from inside an agent that its hooks reach Boop ([ADAPTERS.md](ADAPTERS.md) §6) |
| `tools/webcam/webcam.sh` | The camera recorder ([its README](../tools/webcam/README.md)); `boopctl cam` wraps it |

**Sharing the port.** Only one process can open the serial port, so
`boopctl bridge` owns it and shares it on a Unix socket (`--socket`,
default `$BOOP_BRIDGE` or `/tmp/boop-bridge.sock`). Every line from the
board goes to every client, and each client's lines reach the board whole.
The bridge never waits on a client: one that stops reading and falls 4 MB
behind is dropped. While a bridge runs on that socket, other `boopctl`
commands go through it.

## 3. The debug channel

Over USB the board takes every protocol message
([PROTOCOL.md](PROTOCOL.md)) plus debug messages, whose type starts with
`dbg.`. It ignores debug messages over Bluetooth. Each of these gets a
reply:

| Message | What it does |
| --- | --- |
| `{"t":"dbg.ping"}` | Replies with `fw`, `sha`, `up` (ms since boot), `heap`, `heap_min`, `fps`, `draw_us` and `push_us` (the last frame's drawing and pushing time), `link` (`usb`, `ble` or `none`), `ble` (`off`, `idle`, `adv` or `conn`; at `idle` no Mac can find it), `name` (`Boop-XXXX`), `voice` (the voice assets' version), and `w` and `h` (the screen as drawn) |
| `{"t":"dbg.state"}` | Replies with the device's own view of itself (below) |
| `{"t":"dbg.shot"}` | Replies with a header `{"t":"dbg.shot","w":320,"h":240,"bytes":N,"crc":…}`, then one base64 line: 512 bytes of RGB565 palette (256 little-endian entries), then 76,800 bytes of palette indexes, row by row. `crc` is zlib's CRC-32 of those bytes. It takes about 2.3 s |
| `{"t":"dbg.clock","freeze":T}`, `{…,"step":MS}`, `{…,"run":true}` | Freezes the clock at T (and seeds randomness from T), steps it, or lets it run. A clock a tool froze runs again by itself after 60 s with no `dbg.` message, so a tool that dies can't leave the board stopped |
| `{"t":"dbg.press","ms":N}`, `{"t":"dbg.touch","x":X,"y":Y,"ms":N}` | Holds BOOT, or a touch, for N ms (100 by default), through the same code as real input |
| `{"t":"dbg.pattern"}`, `{…,"fill":N}`, `{…,"target":[x,y]}` | Shows the test pattern, a solid screen of palette index N, or an amber cross at (x, y) on black, until the next `state`. Touches don't tap while it shows |
| `{"t":"dbg.light","bl":0-255,"led":"#RRGGBB"}` | Sets the backlight and the LED (either is optional) until the next `state` |
| `{"t":"dbg.touchcal"}`, `{…,"set":[ax,bx,cx,ay,by,cy]}`, `{…,"clear":true}` | Reads, sets or forgets the touch calibration, x = (ax·raw x + bx·raw y + cx) / 65536 and y alike; replies with `cal`, null when uncalibrated ([DEVICE.md](DEVICE.md) §4) |
| `{"t":"dbg.reset"}` | Forgets everything the Mac said, the moment and any local screen, and freezes the clock at 0. Every scenario starts with it |

If the canvas or the display fails to start, the board prints
`{"t":"dbg.fatal","why":…}` every 2 s instead of running.

What `dbg.state` reports:

| Field | Meaning |
| --- | --- |
| `screen` | `face`, `needs_you`, `no_app` (drawn as the asleep face) or `pattern` |
| `base`, `attn`, `quiet`, `vol` | From the last `state` ([PROTOCOL.md](PROTOCOL.md) §3); `attn` is null unless something needs you |
| `moment` | `{"anim":…,"left_ms":…}` while an animation plays, otherwise null (a mumble on its own leaves it null) |
| `life` | `blink` while Boop blinks, otherwise null |
| `led`, `bl` | The LED's colour and the backlight level |
| `audio` | `playing` while the mouth follows a mumble, and its `syllables`. `out` is what the sound output did: `ready`, `playing`, `lines` finished since boot, and for the last line `syl`, `word` (whether it had one), `plan_ms` (beats × `ms`), `out_ms` (samples rendered), `wall_ms` (the DAC's measured time), `cut` (hushed or replaced) and `errors` (DAC writes that timed out) |
| `sfx` | The last sound cue and when, such as `{"k":"chirp","at":27000}` ([BEHAVIORS.md](BEHAVIORS.md) §4), since tests can't hear |
| `last_input` | The last gesture: `k` (`tap`, `touch`, `talk_on` or `talk_off`), `at`, and `x` and `y` for a touch |
| `rx` | The `state` and `moment` messages received since boot; L4 times hooks by `rx.state` |
| `clock`, `boot`, `touch`, `bat`, `amp` | Bring-up readings: the clock's `now` and `frozen`, BOOT's level, the touch panel's `down`, `irq` and `raw` (x, y, z), the battery in mV (0: the v1 board has none), and whether the amp is on |

The board handles every waiting line before it draws the next frame
([PROTOCOL.md](PROTOCOL.md) §2), so a burst can't overflow its 2 KB
receive buffers. Lines are
handled in order, so a reply reflects every message before it, and a debug
message ends the batch, so injected input and clock steps land between
frames exactly as in the simulator.

**Why screenshots are exact.** The firmware draws every frame into one
8-bit canvas and pushes that to the screen, and the simulator runs the
same drawing code into the same canvas. With a frozen clock and the same
scenario, a device screenshot and a simulator PNG are identical, pixel for
pixel, so any difference is a bug. A screenshot can't show colour
inversion, RGB/BGR order, rotation, the backlight or how the panel really
looks. That's L3's job.

## 4. Scenarios

A scenario is a JSON-lines file in `firmware/test/scenarios/`, played the
same way in the simulator and on the board. This is the start of
`behaviour.jsonl`:

```
// Device behaviour (BEHAVIORS.md §3): press feedback, gestures, push-to-talk
// and its wait for the reply, and the needs-you tap. Shots are the rows' goldens.
{"clock":0}
{"t":"state","v":1,"base":"idle","busy":0,"idle":1,"wait":0}
{"clock":500}
{"input":{"press":"tap"}}
{"clock":516}
{"expect":{"moment":null,"boot":true}}
{"shot":"press-feedback"}
{"clock":600}
{"expect":{"moment":{"anim":"wiggle"},"last_input":{"k":"tap","at":600}}}
{"clock":850}
{"shot":"tap-wiggle"}
```

| Line | Meaning |
| --- | --- |
| `{"clock": ms}` | Freezes the clock at this time since the scenario started |
| A protocol message | Sent as if it came from the Mac |
| A `dbg.` message | Sent as a debug request (§3), such as `{"t":"dbg.pattern"}` |
| `{"input": {"press":"tap"}}` | Presses BOOT: `tap` for 100 ms, `hold` for 800 ms, or `"ms"` for another length |
| `{"input": {"touch":[x,y]}}` | Touches the screen at (x, y) for 100 ms, or `"ms"` |
| `{"shot": "name"}` | Saves a screenshot as `name.png` |
| `{"expect": {…}}` | Reads `dbg.state` once and fails on a mismatch. Only the keys given are compared, recursively |
| `// …` | A comment; blank lines are skipped too |

An `input` line doesn't move the clock: the press stays down until the
clock passes its length, so the tap above lands at 600. Both runners send
`dbg.reset` first, so the board starts each scenario exactly as a fresh
simulator does.

Every screen and state in [BEHAVIORS.md](BEHAVIORS.md) and [UX.md](UX.md)
gets at least one scenario. Their pictures are the golden images in
`firmware/test/golden/<scenario>/`.

## 5. The levels in detail

### L0: unit tests

- **Swift (`make test`):** every part in [ARCHITECTURE.md](ARCHITECTURE.md)
  §3 has tests, each brain runs with no model or network, and the eval
  scenarios run in every mode ([EVALS.md](EVALS.md)).
- **Firmware (`make fw-test`):** line reassembly across BLE packets, the
  device's messages and debug channel, the behaviour state machine
  (including `test_no_change_ever_cuts_hard`: nothing in any state cuts the
  face hard), gestures, drawing and the voice player.
- **The Mac app's look**, for Mac UI changes: run
  `app/.build/debug/Boop --snapshots DIR` and open every PNG against
  [UX.md](UX.md) §7: nothing clipped, no debug data, text readable, the
  Warm Terminal look. The run fails by itself on UX.md §7's contrast.
  There are no goldens.

**Pass:** everything green. New code comes with tests.

### L1: simulator

1. `make sim` (or `tools/boopctl sim <scenario>`) writes PNGs to
   `/tmp/boop-sim/<scenario>/` and compares them with the goldens.
   Unchanged pictures pass.
2. Open every new or changed picture and check it against the spec: the
   right screen and state, eyes centred and readable, text inside its
   area, palette colours, nothing clipped or overlapping.
3. Only then does `tools/boopctl sim <scenario> --accept` update the
   goldens, with a one-line reason in the evidence (§7).

**Pass:** every golden matches, or the changed ones were looked at and
accepted.

### L2: device over USB

1. `make flash`, then `tools/boopctl ping`: `sha` must match the commit
   under test, and `ble` mustn't be `conn`. **One writer only:** a Mac app
   connected over Bluetooth keeps sending its own `state`, which silently
   replaces the test's.
2. `tools/boopctl run`: every `expect` passes, and every screenshot is
   identical to the simulator's.
3. `tools/boopctl perf --motion`: at least 25 fps while moving, at least
   60 KB minimum free heap, and no reset (uptime keeps rising).
4. When a change could leak memory or wedge the board: `tools/boopctl soak`
   (20 minutes by default, with one 35 s silence) ends with no reset, the
   minimum heap within 2 KB of where it stood after the first minute, the
   board still answering, and the plain face back with no moment.

**Pass:** all of the above.

### L3: webcam

At bring-up, and when a new screen or a change in colour or motion lands,
if authorised (§6):

1. **Framing:** `boopctl cam frame` finds the screen by lighting it white
   and then turning the backlight off, and saves the crop to
   `/tmp/boop-cam/crop.json`, turned so USB-C is on the right (`--usb` says
   where it is otherwise). If it finds no screen, skip L3 and say so.
2. **Pattern:** `boopctl cam pattern` samples the test pattern: red reads
   as red (blue means BGR order), white is brighter than black (otherwise
   it's inverted), the UP arrow is at the top and the black bar on the
   USB-C side (rotation). Fix the panel settings until it passes and record
   them in [DEVICE.md](DEVICE.md) §4.
3. **Clips:** `boopctl cam clip <name>` records up to 10 s of a live preset
   with the clock running (`idle`, `needs_you`, `cheer` then a mumble, or
   `tap`) and saves a contact sheet of cropped frames. Compare it with the
   simulator's pictures: recognisably the same, readable, the right
   colours, and moving smoothly with no tearing, stuck frames or flicker.
   `boopctl e2e --clip` films a short Claude session through the pipeline.

**Pass:** the pattern check passes and the clips match the spec. The
camera judges "looks right"; pixel accuracy comes from L2.

### L4: pipeline over USB

This checks the whole path, hook → app → board, without Bluetooth, which
an agent can't use. `make e2e` (`tools/boopctl e2e`) does all of it:

1. `boopctl bridge` owns the serial port on `/tmp/boop-e2e/usb.sock`.
2. The app runs headless with its own state and sockets, never the
   everyday ones:
   `Boop --headless --state-dir /tmp/boop-e2e/state --link usb:/tmp/boop-e2e/usb.sock --socket /tmp/boop-e2e/boop.sock --mode chatty --writer none --name Pip --debug`.
   Chatty's if-else table with no writer makes runs repeatable;
   `--writer apple` lets Apple's model write the words.
3. The fixtures in `app/Tests/Fixtures/hooks/e2e/` go through the real
   `boop-hook`: a Claude session, a Codex approval answered within the 2 s
   grace period, and one left for 10 s. Between payloads they hold
   checkpoints: `expect` (poll `dbg.state` until it matches, within
   `within_ms`, 2000 by default; `shot` on the line saves a screenshot),
   `expect_not` (no match for `for_ms`, or until `until_ms` after the last
   hook), `wait_ms`, and `advance_ms` (moves the app's clock).
4. Latency runs from launching `boop-hook` to the board's `rx.state` going
   up. A hook that changes nothing sends no `state` and is left out.
5. Afterwards it checks the memory's Happened lines and the brain's inputs
   against the fixtures' `expect.json`, that no `PRIVATE_` marker from the
   fixtures reached any app file (`debug.jsonl` included), and, from
   `boop.log`, that every brain moment came after the rules' reaction and
   didn't cut a rule moment short.

**Pass:** every checkpoint matches, and p95 latency from hook to board is
under 200 ms.

`tools/boopctl soak --pipeline` loops the same fixtures for `--minutes`,
with a tap between rounds and a quiet minute at the end. It fails on a
board reset, a minimum-heap drift over 2 KB, audio errors, the app
exiting, or anything left on screen (not the plain face, or `attn` or a
moment still set), and reports checkpoint misses. The CH340 rarely drops
bytes over a long run, so a debug request that loses its reply is retried
once and counted as a link glitch.

### L5: brain

1. `make eval REAL=1` (`boopdev eval --real`) runs every eval scenario in
   every mode with its real brains, 3 times each: Apple's model writes,
   and normal decides with Jev when `BOOP_JEV_KEY` is set (its table
   otherwise). What it reports is in [EVALS.md](EVALS.md) §2.
2. Read about 20 of its passes (`boopdev watch` on the file it names)
   against `steering.md`: are the decisions in character and never
   nagging, the words right for what happened, and the memory lines worth
   keeping?

**Pass:** every scenario passes in every run; Stage 1 answered on the menu
for every pass it didn't refuse; actions dropped fewer than 5% of the
calls handed to them; every input kind's p95 latency is under its
deadline; and the sample reads well. Refusals (a model's guardrail
declining) are reported, not failed: Boop keeps the rules' reaction, and a
refused write leaves the words empty.

### L6: the owner

Only a person can check Bluetooth (launching the app), the mic and speech
recognition, real touches and calibration (`boopctl calibrate`), sound by
ear (`boopctl mumble`, `mumble --board-volume`, `mumble --levels`,
`play needs`), real Claude Code and Codex sessions, the Mac app in the
real menu bar, and how Boop feels. The checks still waiting are in
[PLAN.md](PLAN.md).

## 6. Webcam

The camera is opt-in ([CLAUDE.md](../CLAUDE.md)), and its procedure is the
[`webcam-verify` skill](../skills/webcam-verify/SKILL.md). Only cropped
frames chosen as evidence go into the repo. If framing fails, skip L3 and
report it.

## 7. Evidence

Work that needs a record writes `plan/evidence/<date>-<topic>/README.md`:
what ran, the result, anything accepted or changed and why, and a few
small PNGs (simulator, device screenshot, webcam crop). Link it from
[PLAN.md](PLAN.md). Logs and raw video stay in `/tmp`. The finished v1
build's records are in `plan/evidence/v1-build/`.
