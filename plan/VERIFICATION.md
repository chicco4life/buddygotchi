# Boop: verification

Updated 2026-09-29. How we check that Boop works, including what's on its
screen, without a person watching, and every tool that does it.

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
| L5 Brain | Does Jev behave? | Jev's key in `BOOP_JEV_KEY` |
| L6 Owner | Bluetooth, touch, sound, real agents, how it feels | The owner |

## 2. The tools

**The animation bank and the mood graph.** The bank is where the
device's designs and sounds come from: `make -C internal faces` and
sfxgen (below) build from it.
`node internal/boop-design/boop-mood-spectrum-v2/validate.mjs` checks the
approved graph topology. `node internal/boop-design/boop-sound-bank-v4/source/build.mjs`
builds the portable runtime, offline review and manifests; `--svg` additionally
exports all selections as SVG. Then
`node internal/boop-design/boop-sound-bank-v4/qa/check.mjs` checks coverage,
legacy fingerprints, selection guards, timing and generated audio.
`node internal/boop-design/boop-sound-bank-v4/qa/browser.mjs` runs browser,
cue/frame, loop, text-lane and review-UI checks. Browser dependencies and
overrides are in the [package guide](../internal/boop-design/README.md).
All scripts support `--help`; none contacts JEV, ElevenLabs or a device.
Evidence: [mood design publication](evidence/2026-09-28-mood-design-push/README.md).
These checks are not physical audio tests or the owner's approval of the
new art.

Every tool prints its flags with `--help` (`internal/tools/boopctl
<command> --help`, `.build/debug/boopdev <command> --help`,
`.build/debug/Boop --help`). `Boop` and `boopdev` stop with their usage on
a flag they don't take, `Boop` before anything starts, so a typo can't
launch the menu-bar app or run the whole eval.

**Make targets.** The root `Makefile` has the owner's everyday targets;
`internal/Makefile` has the development ones, run from the repo root as
`make -C internal <target>`.

| Target | What it does |
| --- | --- |
| `make build` | Builds the Mac app, `boop-hook` and `boopdev` in one `swift build`. Importing a target that isn't a declared dependency fails it, so `app/` can't use `internal/` code ([ARCHITECTURE.md](ARCHITECTURE.md) §10) |
| `make run` | Builds, then runs the menu-bar app with Bluetooth. The owner's; never from an agent's shell |
| `make debug` | The same with `--debug` |
| `make dash` | The dashboard for the app `make debug` started, in a second terminal |
| `make day` | What the everyday app did in a day, and why, from the logs `make debug` leaves (`boopctl day`, below); `DATE=YYYY-MM-DD` picks the day, the newest line's by default |
| `make flash` | Builds the firmware and uploads it over USB; `BOOP_PORT` picks the port |
| `make eval` | Builds, then runs the eval scenarios against Jev, 5 runs each for an `always` scenario and 3 for the rest (L5); fails without `BOOP_JEV_KEY` |
| `make clean` | Deletes `.build` and `firmware/.pio` |
| `make -C internal test` | The Swift unit tests, the eval runner included with a scripted brain, through the XCTest shim (`python3 internal/app/tools/test.py`), since there's no Xcode |
| `make -C internal fw` | Builds the firmware for the board |
| `make -C internal fw-test` | The firmware's unit tests on the Mac (`pio test -e native`) |
| `make -C internal sim` | Every scenario in the simulator, against the goldens (L1) |
| `make -C internal e2e` | Builds, then runs the pipeline check (L4) |
| `make -C internal faces` | Regenerates the faces (`firmware/assets/faces.h`, the popover's `app/Boop/Views/FaceDesigns.swift`, the designs' loops for the Mac in `app/BoopKit/Core/FaceLoops.swift`, the frames `fw-test` checks, and the designs' list in `internal/tools/facegen/design/manifest.json`) from the animation bank (`internal/boop-design/boop-sound-bank-v4/`), whose generator it runs with node. It stops if an older mood's design doesn't come out as it was captured, then draws each design at a dozen moments in Google Chrome and fails unless facegen's own drawing matches pixel for pixel in RGB565, a blended pixel within one step (7,970 frames of 704 scenes, 7 minutes or so). Then rerun sfxgen (below) |
| `make -C internal tools` | Makes or refreshes `internal/tools/.venv` (pyserial, Pillow, Textual). `internal/tools/boopctl` makes it on first run |
| `make -C internal tools-test` | The tools' own tests, with no board or camera: `boopctl`'s commands and link, the dashboard (`test_dash.py`), the day's summary (`test_day.py`), the working day's script (`test_workday.py`) and the webcam recorder on synthetic video |

**`internal/tools/boopctl`**, the board over USB, the simulator, the
dashboard and the day's summary. `--port PORT` picks the serial port (default `$BOOP_PORT` or
the first `/dev/cu.usbserial-*`). Without it, while a bridge runs (below),
commands go through the bridge.

| Command | What it does |
| --- | --- |
| `ping` | Prints `dbg.ping`'s vitals ([PROTOCOL.md](PROTOCOL.md) §5) |
| `state` | Prints `dbg.state`, the device's own view of itself |
| `shot [--out FILE]` | Saves a screenshot of the canvas as a PNG (default `/tmp/boop-shot.png`) |
| `send '<json>'` | Sends one message as the Mac would; for a `dbg.*` request it prints the reply |
| `play ANIM\|needs\|pattern` | Makes the board do one thing the Mac can, and checks it took. An animation (`task_complete`, `reply_ready`, `starting`, `stopped`, `error`, `helper_return`, `poked` or `tap_spam`, or the older `cheer` and `wiggle`) plays over `--base` (idle) in `--mood` (happy) at `--vol` (1–10, 6), and `--loops N` (1–6) sends that many loops (without it the moment has none, which plays once); `--variant N`, `--outcome success\|failure` (task_complete) and `--ctx new_task\|session\|continuation` (starting) pick its variation, and it prints the one playing; `--say FEELING` adds a mumble, from the design's voice window, with `--word` and `--seed`. `needs` holds a fake "needs you" for `--seconds` (10) from `--agent` (claude) on `--project` (boopctl) with `--more` (0), and reports whether its performance started and its ding was sent. `pattern` shows the test pattern |
| `mumble [feeling…]` | Plays the Mac's Voice lines for each feeling (all eight by default), without and with a word, and checks each in `audio.out`: syllables, word, and the DAC's time within 10% of beats × `ms`; then that a muted line moves the mouth silently. `--word W` or `--no-word`, `--count N` lines each, `--vol`, `--seed N` to replay a run, `--gap S` between lines (0.8), `--json`. For listening: `--board-volume` plays one line at the volume the board already has; `--levels L…` plays one line at each level, `--rounds N` times (6) |
| `sim [scenario…] [--accept]` | Plays scenarios (all by default) in the simulator into `/tmp/boop-sim/<scenario>/` and compares them with the goldens (L1); `--accept` copies the pictures in |
| `run [scenario…]` | Plays scenarios on the board and diffs each screenshot against the simulator's, threshold 0 (L2), then lets the clock run again |
| `perf [--seconds N] [--motion]` | Samples fps, frame time and heap once a second for N s (30); `--motion` keeps the face moving (L2) |
| `soak [--minutes N] [--seed N] [--vol N] [--out FILE]` | Random, realistic traffic and inputs for N minutes (20), brain reactions with ids and loops among them, at `--vol` (6; 1 is quiet) (L2). `--pipeline` loops the L4 fixtures through the headless app instead, with `--brain scripted\|jev` and `--out DIR` |
| `e2e [fixture…]` | The pipeline check (L4). `--brain scripted\|jev` (scripted), `--out DIR` (`/tmp/boop-e2e-out`), `--clip` to film a Claude session first (L3, with `--camera ID`) |
| `bridge [--socket PATH] [--quiet]` | Owns the serial port and shares it on a Unix socket (below) |
| `cam frame\|pattern\|clip [name]` | The webcam helpers (L3). `--seconds N` for a clip (8, at most 10), `--usb bottom\|right\|top\|left` for framing, `--camera ID` (default `$BOOP_CAMERA` or the built-in camera) |
| `dash [--state-dir DIR] [--socket PATH]` | The live dashboard |
| `day [--state-dir DIR] [--date YYYY-MM-DD] [file…]` | What Boop did in a day, and why, from debug mode's logs: the state directory's `debug.jsonl` and the earlier launches' kept beside it, oldest first (the everyday app's by default), or the files named, oldest launch first. A table by the hour (finishes: task_complete, reply_ready and older logs' cheers; chatter, the brain's reactions and their faces, alerts (a new or different request shown), mood changes, passes, dropped passes, the brain's reactions that didn't happen, pokes and minutes needing you), then the brain's passes and what the dashboard forced, each mood change and what made it, each time something needed you and how long it took to clear, and why reactions didn't happen ([harness/HARNESS.md](harness/HARNESS.md) §9). `--date` defaults to the newest line's day; it exits 1 when that day has no lines |
| `calibrate` | Touch calibration: a person taps crosses on the screen (L6). `--show` prints the stored map, `--show --clear` forgets it |

**`.build/debug/boopdev`**, the developer CLI.

| Command | What it does |
| --- | --- |
| `replay <hooks.jsonl> [--agent claude\|codex] [--gap-ms N] [--states]` | Runs recorded hook payloads through `boop-hook`'s field picking, the adapter and the pipeline (the core and the view) on a virtual clock, and prints each raw event, the core's decisions and the view events. `{"wait_ms":N}` and `{"advance_ms":N}` lines move the clock. `--states` prints only what goes to the device: each `state` and each rule `moment` |
| `replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]` | Sends each payload through the real `boop-hook` to a running app, in real time, and times each `boop-hook` from launch to exit. `{"advance_ms":N}` moves a headless app's clock |
| `voice <feeling\|mood> [word] [--dialect HEX] [--seed N] [--count N] [--json]` | Prints the lines `react` would build ([VOICE.md](VOICE.md) §4), in a feeling or in the one Voice gives a mood's face; dialect `7f3a` and seed 1 by default |
| `eval [--runs N] [--only TEXT] [--always] [--timeline] [--scenarios DIR] [--steering DIR]`, `eval --list` | The eval scenarios against Jev (L5, [EVALS.md](EVALS.md)); `--list` prints each one's case with no key |
| `watch [FILE] [--new]` | Prints a `debug.jsonl`'s view events, passes and actions readably as it grows, waiting for it if it isn't there yet; with no file, the everyday app's. `--new` skips what's already there |
| `hooks status\|install\|remove [claude\|codex] --home DIR [--hook PATH]` | The hook installer, against any HOME ([ADAPTERS.md](ADAPTERS.md)) |

**`.build/debug/Boop`**, the app.

| Way | What it does |
| --- | --- |
| `Boop [--state-dir DIR] [--link ble\|usb:SOCKET\|none] [--debug]` | The menu-bar app, with Bluetooth by default. The owner's. With a state directory other than the everyday one, it never installs or repairs the hooks |
| `Boop --headless --state-dir DIR` | The whole runtime with no UI and no Bluetooth (L4). `--link usb:SOCKET\|none` (none), `--socket PATH` (`DIR/boop.sock`), `--personality boop\|chatter` for this run, `--brain jev\|scripted` (jev, only with `BOOP_JEV_KEY`; scripted answers every pass with an excited "yay", no network), `--name NAME` and `--nature sweet\|cheeky` for a new state directory, `--debug`. On its socket `{"dev":"advance","ms":N}` moves its clock, and `{"dev":"listen","on":true}` and `{"dev":"said","words":"…"}` stand in for push-to-talk's button and mic ([harness/HARNESS.md](harness/HARNESS.md) §9). It keeps its transcript in `DIR/transcript/` and reads it back at launch ([harness/HARNESS.md](harness/HARNESS.md) §5) |
| `--debug`, either way | Prints every hook, view event, action, device line and brain pass as it happens, and writes `DIR/debug.jsonl` for `boopdev watch` and `boopctl dash`; the socket then also takes the dashboard's dev lines ([harness/HARNESS.md](harness/HARNESS.md) §9) |
| `Boop --snapshots DIR` | Renders the popover's panes and the menu-bar icons to PNGs, light and dark, from fixtures, and fails on low contrast (L0). No runtime, no Bluetooth |

**Other tools.**

| Tool | What it does |
| --- | --- |
| `internal/tools/.venv/bin/python internal/tools/voicegen/voicegen.py [--out FILE] [--wav-dir DIR]` | Rebuilds the voice assets, `firmware/assets/voice.h`, with macOS `say` ([VOICE.md](VOICE.md) §8); `--wav-dir` also writes every clip as a WAV |
| `node internal/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]` | Rebuilds the sound effects, `firmware/assets/sfx.h`, from the animation bank's synthesiser and timelines, for the designs facegen lists, so after `make -C internal faces` ([VOICE.md](VOICE.md) §10); `--wav-dir` also writes every clip as a WAV |
| `internal/tools/.venv/bin/python internal/tools/fontgen/fontgen.py [--ttf-dir DIR]` | Rebuilds the device's fonts, `firmware/assets/fonts.h`, from Geist Mono ([DEVICE.md](DEVICE.md) §6); the `.ttf` files are in `landing/node_modules` after `npm ci` there, by default |
| `internal/tools/.venv/bin/python internal/tools/facegen/facegen.py [--check]` | What `make -C internal faces` runs; without `--check` it skips the comparison with Chrome |
| `python3 internal/tools/workday/workday.py plan\|run\|report` | A scripted 8-hour working day through `Boop --headless` and its brain on a compressed clock, and a report of what Boop did hour by hour: mood changes, reactions by kind of line, faces, and the day's words (L5, [EVALS.md](EVALS.md) §5). `run --state DIR` (short, under `/tmp`; it's deleted first), `--seed N` (1), `--brain jev\|scripted` (jev, with `BOOP_JEV_KEY`), `--personality`, `--out DIR`, `--verbose`; `report FILE…` takes `debug.jsonl` files, `--json`; `check FILE…` holds each to the liveliness limits and exits 1 if one fails |
| `internal/tools/webcam/webcam.sh list\|record\|analyze` | The camera recorder ([its README](../internal/tools/webcam/README.md)); `boopctl cam` wraps it |
| `internal/skills/doctor/doctor.sh` | Checks from inside an agent that its hooks reach Boop; `--headless` against a throwaway app ([ADAPTERS.md](ADAPTERS.md) §6) |

**Sharing the port.** Only one process can open the serial port, so
`boopctl bridge` owns it and shares it on a Unix socket (`--socket`,
default `$BOOP_BRIDGE` or `/tmp/boop-bridge.sock`). Every line from the
board goes to every client, and each client's lines reach the board whole.
The bridge never waits on a client: one that stops reading and falls 4 MB
behind is dropped. The app's USB link (`--link usb:SOCKET`) and other
`boopctl` commands can use the board at the same time.

## 3. The debug channel

Over USB the board takes every protocol message plus the `dbg.*`
messages that tests use: vitals, the device's own view of itself,
screenshots, a frozen clock, injected presses and touches, the test
pattern, the lights, touch calibration and a reset. Every one, its reply
and every field of `dbg.state` are in [PROTOCOL.md](PROTOCOL.md) §5. The
board ignores them over Bluetooth.

The board handles waiting lines in order before it draws the next frame,
and a debug message ends the batch ([PROTOCOL.md](PROTOCOL.md) §2). So a
reply reflects every message before it, and injected input and clock
steps land between frames exactly as in the simulator.

**Why screenshots are exact.** The firmware draws every frame into one
8-bit canvas and pushes that to the screen, and the simulator runs the
same drawing code into the same canvas. With a frozen clock and the same
scenario, a device screenshot and a simulator PNG are identical, pixel for
pixel, so any difference is a bug. A screenshot can't show colour
inversion, RGB/BGR order, rotation, the backlight or how the panel really
looks. That's L3's job.

## 4. Scenarios

A scenario is a JSON-lines file in `internal/firmware/test/scenarios/`,
played the same way in the simulator and on the board. This is the start
of `behaviour.jsonl`:

```
// Device behaviour (BEHAVIORS.md §3): press feedback, gestures, and the
// needs-you tap. Shots are the rows' goldens.
{"clock":0}
{"t":"state","v":1,"base":"idle","busy":0}
{"clock":500}
{"input":{"press":"tap"}}
{"clock":516}
{"expect":{"moment":null,"boot":true}}
{"shot":"press-feedback"}
{"clock":600}
{"expect":{"moment":{"anim":"poked","left_ms":2800},"last_input":{"k":"tap","at":600}}}
{"clock":850}
{"shot":"tap-poked"}
```

| Line | Meaning |
| --- | --- |
| `{"clock": ms}` | Freezes the clock at this time since the scenario started |
| A protocol message | Sent as if it came from the Mac |
| A `dbg.` message | Sent as a debug request, such as `{"t":"dbg.pattern"}` |
| `{"input": {"press":"tap"}}` | Presses BOOT for 100 ms, or `"ms"`; 400 ms or more is push-to-talk (the scenarios write `"press":"hold"`) |
| `{"input": {"touch":[x,y]}}` | Touches the screen at (x, y) for 100 ms, or `"ms"` |
| `{"shot": "name"}` | Saves a screenshot as `name.png` |
| `{"expect": {…}}` | Reads `dbg.state` once and fails on a mismatch. Only the keys given are compared, recursively |
| `// …` | A comment; blank lines are skipped too |

An `input` line doesn't move the clock: the press stays down until the
clock passes its length, so the tap above lands at 600. Both runners send
`dbg.reset` first, so the board starts each scenario exactly as a fresh
simulator does.

Every screen and state in [BEHAVIORS.md](BEHAVIORS.md)
gets at least one scenario. Their pictures are the golden images in
`internal/firmware/test/golden/<scenario>/`.

## 5. The levels in detail

### L0: unit tests

- **Swift (`make -C internal test`):** every part in
  [ARCHITECTURE.md](ARCHITECTURE.md) §3 has tests; the harness and actions
  run with a scripted brain and no network, and the eval runner is tested
  the same way ([EVALS.md](EVALS.md)). `CoreFuzzTests` plays 20,000 random
  hooks from three sessions (Claude with subagents, and Codex) into the
  pipeline, with ticks and clock jumps, and checks after each that HISTORY
  and the screen agree (every `tool` wait view event is for a session
  shown waiting, nothing plays or wakes the brain while something needs you,
  and one request's number never changes its agent or project), and that
  a subagent's end, or a turn-level hook from inside one, answers only
  that subagent's request, isn't activity, and makes its session work
  again only while its turn goes on, and its start changes none of that.
  It also checks what the agents are doing shows only in the working
  look, every variation is one the visual has, and the rules' one-shots
  never go out while something needs you or with an `id`, the error one
  at most every 30 s.
- **Firmware (`make -C internal fw-test`):** line reassembly across
  Bluetooth packets, screenshot encoding, the clock and gestures
  (`test_link`); the messages, debug channel and inputs (`test_device`);
  the behaviour state machine, to the millisecond, including
  `test_no_change_ever_cuts_hard` and
  `test_nothing_cuts_hard_as_it_plays_out`, which hold every change and
  every moment running out (a reaction's borrowed face, a finish's loops
  and its line, a one-shot and a poke included), in the first pack's
  moods and the new moods' flip-books, to the face never cutting hard:
  the same design at the same moment, or the design's own shut eyes
  showing; and what the agents are doing, the one-shots and the finish
  with their facts and voice window, taps in a row and what shows first
  (`test_behaviour`); the canvas and
  renderer, the bubble in the bottom lane included (`test_canvas`,
  `test_face`); the animation bank's player
  against facegen's frames, every mood, state and variation, and the
  variations' host facts (`test_scene`); the voice
  player (`test_voice`); and the sound effects' assets, policies, timing
  and mixer (`test_effects`).
- **The Mac app's look**, for Mac UI changes: run
  `.build/debug/Boop --snapshots DIR` and open every PNG and check:
  nothing clipped, no debug data, text readable, the Warm Terminal
  look. The run fails by itself on low contrast.
  There are no goldens.

**Pass:** everything green. New code comes with tests.

### L1: simulator

1. `make -C internal sim` (or `internal/tools/boopctl sim <scenario>`)
   writes PNGs to `/tmp/boop-sim/<scenario>/` and compares them with the
   goldens. Unchanged pictures pass.
2. Open every new or changed picture and check it against the spec: the
   right screen and state, eyes centred and readable, text inside its
   area, palette colours, nothing clipped or overlapping.
3. Only then does `internal/tools/boopctl sim <scenario> --accept` update
   the goldens, with a one-line reason in the evidence (§7).

**Pass:** every golden matches, or the changed ones were looked at and
accepted.

### L2: device over USB

1. `make flash`, then `internal/tools/boopctl ping`: `sha` must match the
   commit under test, and `ble` mustn't be `conn`. **One writer only:** a
   Mac app connected over Bluetooth keeps sending its own `state`, which
   silently replaces the test's.
2. `internal/tools/boopctl run`: every `expect` passes, and every
   screenshot is identical to the simulator's.
3. `internal/tools/boopctl perf --motion`: a frame drawn in every second
   while moving, no sampled frame taking over 40 ms to draw and push, at
   least 60 KB minimum free heap, and no reset (uptime keeps rising). A
   frame is drawn only when the picture changes, and the designs step a
   few times a second, so `fps` follows the design rather than the board,
   and a second of a slow one draws only a few frames
   ([DEVICE.md](DEVICE.md) §6).
4. When a change could leak memory or wedge the board:
   `internal/tools/boopctl soak` (20 minutes by default, with one 35 s
   silence halfway) ends with no reset, the minimum heap within 2 KB of
   where it stood after the first minute, the board still answering, no
   audio errors, the plain face back with no moment or borrowed face
   (within 75 s of calm), and one `ended` for every reaction it sent
   ([PROTOCOL.md](PROTOCOL.md) §4), short only by as many lines as were
   lost. It reports the lines the board never got (from `dbg.state`'s
   `rx`), lines that came back torn, and debug replies it had to ask for
   again.

**Pass:** all of the above.

### L3: webcam

At bring-up, and when a new screen or a change in colour or motion lands,
if authorised (§6):

1. **Framing:** `internal/tools/boopctl cam frame` finds the screen by
   lighting it white and then turning the backlight off, and saves the
   crop to `/tmp/boop-cam/crop.json`, turned so USB-C is on the right
   (`--usb` says where it is otherwise). If it finds no screen, skip L3
   and say so.
2. **Pattern:** `internal/tools/boopctl cam pattern` samples the test
   pattern: red reads as red (blue means BGR order), white is brighter
   than black (otherwise it's inverted), the UP arrow is at the top and
   the black bar on the USB-C side (rotation). Fix the panel settings
   until it passes and record them in [DEVICE.md](DEVICE.md) §4.
3. **Clips:** `internal/tools/boopctl cam clip <name>` records up to 10 s
   of a live preset with the clock running (`idle`, `needs_you`, `cheer`
   then a mumble, or `tap`) and saves a contact sheet of cropped frames.
   Compare it with the simulator's pictures: recognisably the same,
   readable, the right colours, and moving smoothly with no tearing, stuck
   frames or flicker. `internal/tools/boopctl e2e --clip` films a short
   Claude session through the pipeline.

**Pass:** the pattern check passes and the clips match the spec. The
camera judges "looks right"; pixel accuracy comes from L2.

### L4: pipeline over USB

This checks the whole path, hook → app → board, without Bluetooth, which
an agent can't use. `make -C internal e2e` (`internal/tools/boopctl e2e`)
does all of it:

1. `boopctl bridge` owns the serial port on `/tmp/boop-e2e/usb.sock`.
2. The app runs headless with its own state and sockets, never the
   everyday ones:
   `.build/debug/Boop --headless --state-dir /tmp/boop-e2e/state --link usb:/tmp/boop-e2e/usb.sock --socket /tmp/boop-e2e/boop.sock --brain scripted --name Pip --debug`.
   The scripted brain makes runs repeatable; `boopctl e2e --brain jev`
   asks Jev, with `BOOP_JEV_KEY`.
3. The fixtures in `internal/app/Tests/Fixtures/hooks/e2e/` go through the
   real `boop-hook`: a Claude session, a Codex approval answered within
   the 2 s grace period, and one left for 10 s. Between payloads they hold
   checkpoints: `expect` (poll `dbg.state` until it matches, within
   `within_ms`, 2000 by default; `shot` on the line saves a screenshot),
   `expect_not` (no match for `for_ms`, or until `until_ms` after the last
   hook), `wait_ms`, and `advance_ms` (moves the app's clock).
4. Latency runs from launching `boop-hook` to the board's `rx.state` going
   up. A hook that changes nothing sends no `state` and is left out.
5. Afterwards it checks the view events' lines in `debug.jsonl` against
   the fixtures' `expect.json`, that no `PRIVATE_` marker from the
   fixtures reached any app file (`debug.jsonl` and the transcript
   included) but `PRIVATE_PROMPT` and `PRIVATE_CLOSING`, which mark your
   prompt and the agent's last message ([ADAPTERS.md](ADAPTERS.md) §2), and, from `boop.log`, that every
   brain moment came after the rules' reaction and didn't cut a rule's
   line short (it may play over an animation, [ARCHITECTURE.md](ARCHITECTURE.md) §3.2),
   and that the board said how every brain moment it was sent ended
   (`ended`, [PROTOCOL.md](PROTOCOL.md) §4). It lists, for the record,
   the ones the board said a newer moment cut short.

**Pass:** every checkpoint matches, and p95 latency from hook to board is
under 200 ms.

`internal/tools/boopctl soak --pipeline` loops the same fixtures for
`--minutes`, with a tap between rounds and a quiet minute at the end. It
fails on a board reset, a minimum-heap drift over 2 KB, audio errors, the
app exiting, or anything left on screen (not the plain face, or `attn` or
a moment still set), and reports checkpoint misses. The CH340 now and then
drops bytes over a long run, so a debug request that loses its reply is
retried once and counted as a link glitch.

### L5: brain

1. `make eval` (`.build/debug/boopdev eval`, with `BOOP_JEV_KEY`) runs
   every eval scenario against Jev, 5 times each for an `always` one and
   3 for the rest. What it reports is in [EVALS.md](EVALS.md) §2.
2. Read a sample of its passes (`boopdev watch` on the file it names)
   against the steering files (`plan/steering/`): are the reactions and
   mood changes in character and never nagging, and the words and how
   long each face holds right for what happened?
3. After a change to the steering files or the questions, the working
   day ([EVALS.md](EVALS.md) §5): `workday.py run` twice before the
   change and twice after, same seed, and `workday.py report` and
   `workday.py check` on each.
   How often the mood changes per hour, whether a routine line changed
   it, and how often, with which faces and which words Boop reacts,
   before against after.

**Pass:** every scenario passes in every run, but for known gaps
([EVALS.md](EVALS.md) §1), and every `always` one does; no pass is dropped; the
slowest pass is under the 1.5 s deadline; and the sample reads well.

### L6: the owner

Only a person can check Bluetooth (`make run`), real touches and
calibration (`boopctl calibrate`), sound by ear (`boopctl mumble`,
`mumble --board-volume`, `mumble --levels`, `play needs`), real Claude
Code and Codex sessions, the Mac app in the real menu bar, and how Boop
feels. A day of real use under `make debug` reads back with `make day`:
what Boop did each hour and why, relaunches included.

## 6. Webcam

The camera is opt-in ([CLAUDE.md](../CLAUDE.md)), and its procedure is the
[`webcam-verify` skill](../internal/skills/webcam-verify/SKILL.md). Only
cropped frames chosen as evidence go into the repo. If framing fails, skip
L3 and report it.

## 7. Evidence

Work that needs a record writes `plan/evidence/<date>-<topic>/README.md`:
what ran, the result, anything accepted or changed and why, and a few
small PNGs (simulator, device screenshot, webcam crop). Logs and raw video stay in `/tmp`. The finished v1
build's records are in `plan/evidence/v1-build/`.
