# Boop: verification

Updated 2026-09-26. How we check that Boop works, especially what's on its
screen, without a person watching. [PLAN.md](PLAN.md) says which checks
each milestone must pass. It builds on the previous generation's
`buddyctl.py` (USB commands, screenshots, golden images) and the opt-in
webcam recorder in `tools/webcam/`.

## 1. The loop

Every change goes around the same loop, stopping at the first level that
fails:

```
 change ─► L0 unit tests ─► L1 simulator ─► flash ─► L2 device over USB ─► L3 webcam ─► commit
            (logic)          (look at the     │       (same pixels as       (the real
                              PNGs)           │        the simulator?)       panel)
                                              └─ skip L2–L3 for Mac-only changes
```

Pipeline, brain and soak checks (L4–L5) run at the milestones that need
them. Checks that need a person (L6) go on the morning checklist.

Each level answers a different question:

| Level | Question | Needs |
| --- | --- | --- |
| L0 Unit tests | Is the logic right? | Nothing |
| L1 Simulator | Does the renderer draw what we meant? | Nothing: the renderer builds on the Mac |
| L2 Device over USB | Does the board do and draw exactly that? | The board on USB |
| L3 Webcam | Does the physical panel show it correctly (colours, orientation, readability)? | The board facing the camera; opt-in (§6) |
| L4 Pipeline | Does a real hook event reach the screen? | The board on USB; no Bluetooth |
| L5 Brain | Does the brain behave on real inputs? | Apple's on-device model, and Jev's key to check Jev |
| L6 Person | Bluetooth, mic, touch accuracy, sound, real agents | The owner, in the morning |

## 2. The tools

| Tool | What it is |
| --- | --- |
| `make test` | Swift unit tests. There's no Xcode here, so this runs the XCTest shim: `python3 app/tools/test.py`, which runs `swift run BoopTests` |
| `make eval` | The harness eval scenarios ([EVALS.md](EVALS.md)): `boopdev eval` |
| `make fw-test` | Firmware unit tests on the Mac: `pio test -e native` |
| `make sim` / `tools/boopctl sim` | The simulator. It builds the same drawing and behaviour code as the firmware for the Mac, runs a scenario, and writes PNGs |
| `tools/boopctl` | The new device tool, replacing `buddyctl.py`. It's Python in `tools/.venv` (pyserial, Pillow), created by `make tools` |
| `tools/boopctl bridge` | Owns the USB serial port and shares it through a Unix socket (`--socket`, default `$BOOP_BRIDGE` or `/tmp/boop-bridge.sock`), so the Mac app and other `boopctl` commands can use the board at the same time. Every line from the board goes to every client, and each client's lines reach the board whole. While a bridge runs, other `boopctl` commands (with `BOOP_BRIDGE` set to its socket, if it isn't the default) go through it instead of opening the port |
| `tools/webcam/webcam.sh` | The existing AVFoundation recorder and frame extractor. `boopctl cam …` wraps it. `make webcam-test` tests it on synthetic video and never opens a camera |
| `Boop --snapshots DIR` | Renders the Mac app's popover (seven overview states, including listening and a refused mic, the whole settings pane, the four setup steps) and the menu-bar icons to PNGs, in light and dark, from fixed fixtures, then exits. No runtime, Bluetooth or microphone; the agents' settings it reads are in a throwaway HOME |
| `boopdev` | A Swift CLI in the app package for replaying hooks, running the brain on recorded inputs, and printing the memory files. `boopdev replay <fixture>` alone runs the payloads through the hook's field picking, the adapter and the core on a virtual clock and prints every decision (`--states` for snapshots only); with `--socket` it sends them through the real `boop-hook` to a running app. `boopdev memory --state-dir DIR` prints the memory files as the store reads them, and the snapshot days. `boopdev voice <feeling> [word] --count N [--why]` prints the lines `react` would build, and with `--why` every rejected try. `boopdev brain [--classifier rules\|jev] [--writer apple\|none\|deepseek] [--inputs DIR] [--memory DIR] [--steering FILE] [--out FILE] [--gap-min N] [--print]` runs L5: recorded inputs through the real pipeline (§5). `boopdev eval [--classifier rules\|jev] [--writer none\|apple] [--only TEXT] [--json FILE]` runs the harness eval scenarios ([EVALS.md](EVALS.md)). `boopdev watch FILE [--new]` follows a brain debug log as it grows and prints each pass and aside readably (HARNESS.md §8). `boopdev talk "<words>" --socket PATH` hands a push-to-talk transcript to a running headless app. `boopdev hooks status\|install\|remove [claude\|codex] --home DIR` runs the hook installer against any HOME |

`boopctl` subcommands:

| Command | Does |
| --- | --- |
| `ports` | List USB serial ports |
| `flash [--env cyd24]` | Build and upload the firmware |
| `ping` | Firmware version and git SHA, uptime, free and minimum heap, fps, link state |
| `state` | The device's own view of itself (§3) |
| `send '<json>'` | Send one protocol message, exactly as Bluetooth would |
| `run <scenario>` | Play a scenario on the device (§4) and save its screenshots |
| `sim <scenario>` | Play the same scenario in the simulator and save its PNGs |
| `shot --out x.png` | Screenshot the device's canvas, at the size its `dbg.shot` header gives |
| `diff a.png b.png` | Pixel diff. Exits non-zero past a threshold and writes a highlighted diff image. Pictures of different sizes differ in every pixel, and their diff image shows the two side by side |
| `press tap\|hold [--ms N]` | Inject a BOOT press |
| `touch X Y [--ms N]` | Inject a touch at screen coordinates |
| `clock freeze T \| step MS \| run` | Control the device clock for repeatable frames |
| `pattern` | Show the bring-up test pattern |
| `mumble [feeling…] [--word W \| --no-word] [--count N] [--vol N] [--seed N] [--json]` | F5's L2 check, and for hearing Boop by hand. Plays N lines built by the Mac's Voice (`boopdev voice --json`) for every feeling (or the ones named), without and then with its usual word, and checks `audio.out` in `dbg.state` for each: the syllable count, the word, and the duration the DAC took within 10% of beats × `ms`. Then checks that a muted line moves the mouth and plays nothing. It prints its seed, and `--seed` plays the same lines again |
| `say [feeling] [--word W] [--seed N]` | One line with its word at the end (the feeling's usual word by default), checked as `mumble` checks it. It sends no `state`, so the line plays at the volume the board already has: the Mac app's when it's connected, for trying the app's volume setting. It prints that volume, and says so instead of playing when the board is muted, quiet or showing needs you |
| `volume [level…] [--rounds N]` | For comparing volumes by ear. Plays one fixed line at each level in turn (1 then 10 by default), for 6 rounds, and says whether the board played each one in full |
| `sound [chirp] [--vol N]` | Plays the needs-you chirp, the only sound cue, the way the Mac causes it: with a new `attn`, then cleared. Checks `sfx` in `dbg.state` |
| `moment [anim] [--say FEELING [--word W]] [--base B] [--vol N]` | Plays one animation from the set (`cheer`, `wiggle`, `listening`; [BEHAVIORS.md](BEHAVIORS.md) §5), a mumble on its own (`--say` with no anim), or both, and checks that the device took it. `moment stop` sends the empty moment ([PROTOCOL.md](PROTOCOL.md) §3) and reports whether `listening` is still playing |
| `needs [--seconds S] [--agent A] [--project P] [--more N] [--vol N]` | Holds a fake "needs you" (10 s by default), printing the screen, light, backlight and the chirp once, then clears it; Ctrl-C clears it early |
| `perf --seconds N [--motion]` | Sample fps and heap over time; `--motion` plays `cheer`, `wiggle` and `listening` back to back so every sample is mid-motion, then the empty moment |
| `e2e [--writer none\|apple] [fixture…]` | The L4 pipeline check (`make e2e`): bridge, headless app, the J1 fixtures through the real `boop-hook`, checkpoints, latency, memory and ordering |
| `e2e --soak MIN [--writer none\|apple]` | J2's pipeline soak: the same fixtures on a loop for MIN minutes, a tap on the board between rounds, then a quiet minute. Samples `dbg.ping`, `audio.out.errors` and the app's memory; fails on a board reset, a heap-minimum drift over 2 KB, audio errors, the app exiting, or anything left on screen (not the plain face, `attn` or a moment) at the end. Checkpoint misses are counted and reported. A debug request that loses its reply (the CH340 rarely drops bytes over a long run) is retried once and counted as a link glitch |
| `soak --minutes N` | Random, realistic traffic and inputs (with one 35 s silence), then check for resets, a drifting heap minimum, and that calm snapshots bring back the plain face |
| `cam frame\|pattern\|clip <name>` | Webcam helpers (L3 in §5). Clips are live presets: `idle`, `needs_you`, `cheer` (then a mumble) and `tap` |
| `calibrate` | Touch calibration. Needs a person to tap 4 amber crosses 20 px in from the corners, then one in the middle to check; the crosses are placed from the screen size the board reports in `dbg.ping` (320×240). It fits a raw → screen map and the board keeps it in NVS for that screen and rotation. `--show` prints the stored map, `--show --clear` forgets it |

## 3. The debug channel

Over USB, the firmware accepts every normal protocol message
([PROTOCOL.md](PROTOCOL.md)) plus debug messages whose type starts with
`dbg.`. Debug messages are ignored over Bluetooth.

| Message | Reply |
| --- | --- |
| `{"t":"dbg.ping"}` | `{"t":"dbg.ping","fw":…,"sha":…,"up":ms,"heap":…,"heap_min":…,"fps":…,"link":"usb\|ble\|none","ble":"off\|idle\|adv\|conn","name":"Boop-XXXX","voice":…,"w":320,"h":240}`. `ble` is Bluetooth's state (`idle` is neither advertising nor connected, so no Mac can find it), `name` the advertised name, `voice` the voice assets' version, and `w`/`h` the screen as drawn |
| `{"t":"dbg.state"}` | `{"t":"dbg.state","screen":"face\|needs_you\|no_app\|pattern" (`no_app` draws the asleep face),"base":…,"attn":…,"moment":{"anim":…,"left_ms":…},"life":…,"quiet":…,"vol":0-10,"led":"#RRGGBB","audio":{"playing":…,"syllables":…},"last_input":…}` |
| `{"t":"dbg.shot"}` | A header line `{"t":"dbg.shot","w":320,"h":240,"bytes":N,"crc":…}`, then one line of base64: 512 bytes of RGB565 palette (256 little-endian entries) followed by 76,800 bytes of pixel indexes, row by row. `crc` is the CRC-32 (as zlib's) of those bytes |
| `{"t":"dbg.clock","freeze":T}` / `{"step":MS}` / `{"run":true}` | Freeze the clock at T (which also seeds randomness from T), step it, or let it run |
| `{"t":"dbg.press","ms":N}` / `{"t":"dbg.touch","x":…,"y":…,"ms":N}` | Inject input through the same code path as real input |
| `{"t":"dbg.pattern"}` / `{"fill":N}` / `{"target":[x,y]}` | Show the test pattern, a solid screen of palette index N, or an amber calibration cross at (x, y) on black, until the next `state` |
| `{"t":"dbg.touchcal"}` / `{"set":[ax,bx,cx,ay,by,cy]}` / `{"clear":true}` | Read, set or forget the touch calibration: x = (ax·raw x + bx·raw y + cx) / 65536, and y alike. The board keeps it in NVS with the screen size and rotation it was set on, and ignores a stored map for any other (the portrait build's, or one from before `kRotation` changed). It replies with `cal` (null when uncalibrated, which uses the default raw range turned with the rotation) |
| `{"t":"dbg.light","bl":0-255,"led":"#RRGGBB"}` | Set the backlight and the RGB LED (both optional), for bring-up and webcam framing |
| `{"t":"dbg.reset"}` | Forget everything the Mac has said, the moment and the local screen, and freeze the clock at 0. Every scenario starts with it |

At 460800 baud a screenshot takes about 2.3 s. `dbg.ping` also reports
`draw_us` and `push_us`, the last frame's drawing and pushing time.
`dbg.state` also carries the behaviour's own view: `life` (`blink` while
Boop blinks, otherwise null), and `sfx`, the last sound cue with its time
(`chirp`, for tests, which can't hear). A mumble on its own leaves
`moment` null; `audio.syllables` shows it. `audio.playing` is true while the mouth follows a
mumble. `audio.out` is what the sound output did: `ready` (the DAC
started), `playing` (a line or cue, amp on), `lines` finished since boot,
and the last line's `syl`, `word`, `plan_ms` (beats × `ms`), `out_ms`
(samples rendered), `wall_ms` (the DAC's measured pace over those
samples), `cut` (hushed or replaced) and `errors` (DAC writes that timed
out). `dbg.state` also carries bring-up readings: `clock` (`now`, `frozen`), `boot` (BOOT's level), `touch`
(`down`, `irq`, `raw` as x, y, z), `bat` in mV (0 on the v1 board, which has no battery), `amp` and `bl`, and `rx`, the
`state` and `moment` messages received since boot (`{"state":N,"moment":M}`),
which L4 uses to time a hook's `state` reaching the board.

The board handles one message per loop pass, so a reply always reflects
every message sent before it.

**Why screenshots are exact.** The firmware draws every frame into one
8-bit canvas and pushes that to the screen, so the canvas *is* the picture.
The simulator runs the same drawing code into the same canvas format. With
a frozen clock and the same scenario, a device screenshot and a simulator
PNG should be identical, pixel for pixel. Any difference is a bug in the
firmware or its inputs, not noise.

What a screenshot can't show: colour inversion, RGB/BGR order, rotation,
backlight, and how the panel actually looks. That's what the webcam level
(L3) is for.

## 4. Scenarios

A scenario is a JSON-lines file in `firmware/test/scenarios/`. The same file
runs in the simulator and on the device:

```json
{"clock": 0}
{"t":"state","v":1,"base":"working","busy":1,"idle":0,"wait":0}
{"clock": 800}
{"shot": "working"}
{"t":"moment","anim":"cheer","ttl":5}
{"clock": 1400}
{"shot": "cheer-peak"}
{"expect": {"screen":"face","moment":{"anim":"cheer"}}}
{"input": {"press":"tap"}}
{"expect": {"moment":null}}
```

| Line | Meaning |
| --- | --- |
| `{"clock": ms}` | Set the frozen clock to this time since the scenario started |
| A protocol message | Sent as if it came from the Mac |
| A `dbg.` message | Sent as a debug request (§3), such as `{"t":"dbg.pattern"}` |
| `{"input": …}` | Inject a press or touch |
| `{"shot": "name"}` | Save a picture as `name.png` |
| `{"expect": {…}}` | Read `dbg.state` once and compare; fail on mismatch. Only the keys given are compared, recursively |
| `// …` | A comment; blank lines are skipped too |

`input` lines don't move the clock: an injected press or touch stays down
until the clock passes its duration (100 ms for a tap, 800 ms for a hold,
or `"ms"`), so a scenario steps the clock past it. The simulator starts
with its clock frozen at 0; the board's runs until the first `clock` line.
Both runners send `dbg.reset` first, so the board starts each scenario
exactly as a fresh simulator does. `boopctl run` plays each scenario in the simulator first, then on the
board, and diffs every shot against the simulator's with threshold 0.

Every screen and state in [BEHAVIORS.md](BEHAVIORS.md) and [UX.md](UX.md)
gets at least one scenario. Their pictures become the **golden images** in
`firmware/test/golden/`.

## 5. The levels in detail

### L0: unit tests

- **Swift (`make test`):** every module in [ARCHITECTURE.md](ARCHITECTURE.md)
  §3 has tests. That covers adapter mapping, core rules (screen priority,
  needs you, quiet, chatter, which inputs reach the brain), each action's
  own checks, Voice (dialect, determinism, the English check), memory
  limits and snapshots, the harness with fake brains (the menu check,
  what's left for the writer, a failed or late stage, one pass at a time,
  what you say cancelling, and the log), the transcript's window, each
  brain on its own with no model or network (the rules classifier's rows,
  Jev's questions to a fake server, what Apple's model is asked), and
  device link message encoding.
- **Firmware (`make fw-test`):** the protocol parser, line reassembly across
  BLE packets, the behaviour state machine (screen priority, the needs-you
  chirp, moment expiry, the 30 s no-app timeout), input gestures, and
  canvas primitives.

**Pass:** everything green. New code comes with tests.

**The Mac app's look** (Mac-only UI changes): build, run
`app/.build/debug/Boop --snapshots DIR`, and open every PNG, in both
appearances. Check it against [UX.md](UX.md) §7: nothing clipped or cut
off, no debug data, text readable on its background, and the panes in the
cream look. There are no goldens. How it feels in the menu bar (opening,
resizing, typing, switches) is the owner's (L6).

### Harness evals

Named scenarios for what the harness should do, given events, taps and
talk over time. They're deterministic and part of L0: `make test` runs
them, and `make eval` prints each one's result. How they work and what each
checks is in [EVALS.md](EVALS.md).

**Pass:** every scenario passes.

### L1: simulator

1. `tools/boopctl sim` runs every scenario and writes PNGs to
   `/tmp/boop-sim/<scenario>/`.
2. They're compared with the goldens. Unchanged pictures pass
   automatically.
3. **New or changed pictures are looked at.** The agent opens each one and
   checks it against the spec: the right screen and state, eyes centred and
   readable, text inside its area and legible, colours from the palette,
   nothing clipped or overlapping.
4. A golden is only updated after that look, with a one-line reason in the
   milestone's evidence notes.

**Pass:** all goldens match, or changed ones are reviewed and accepted.

### L2: device over USB

1. `make flash`, then `tools/boopctl ping`. The SHA must match the commit
   under test. Also check that `link` isn't `ble`. **One writer only:** if
   the Mac app is connected over Bluetooth, its `state` messages silently
   replace the test's. The previous generation recorded a whole set of
   goldens that way before anyone noticed.
2. `tools/boopctl run <scenario>` for every scenario. Each `expect` must
   pass.
3. Each device screenshot must be **identical** to the simulator's picture
   for the same scenario and shot (`boopctl diff`, threshold 0).
4. `tools/boopctl perf --seconds 30` during a motion scenario: at least 25 fps
   while moving, minimum free heap at least 60 KB, and no reset (uptime keeps
   rising).
5. At milestones marked *soak*: `tools/boopctl soak --minutes 20` must end
   with no reset, no drift in minimum heap, and the device still answering.

**Pass:** all of the above.

### L3: webcam

This checks what only the real panel can show. It runs:

- at bring-up (the test pattern);
- whenever a new screen or a change in colours or motion lands;
- once more for the final pass.

1. **Framing** (once per run): `boopctl cam frame` takes one still with the
   screen solid white and one with the backlight off, finds the region that
   changed most, and saves a crop box in `/tmp/boop-cam/crop.json`. If no screen is
   found, skip L3 for the rest of the run and say so in the report. The board
   sits sideways, with USB-C to the right in the camera's view (`--usb`
   says where it is otherwise). The crop is turned so USB-C is on the right,
   320×240, before judging orientation.
2. **Pattern** (bring-up): `boopctl cam pattern` shows the test pattern,
   captures it, and samples the colour blocks. It checks that red reads as
   red (not blue, which would mean BGR order), that white is bright and
   black is dark (not inverted), that the UP arrow is at the top, and that
   the black USB-C bar is on the USB-C side (rotation). Fix the panel
   settings in the firmware until it passes, then record them in
   [DEVICE.md](DEVICE.md) §4.
3. **Screens and motion:** `boopctl cam clip <name>` records up to 10 s
   while a live preset plays with the clock running (scenarios freeze the
   clock, so they wouldn't move), crops each frame, and saves a contact sheet. The
   agent compares the frames with the simulator's pictures: is it recognisably
   the same, readable, the right colours, and moving smoothly with no tearing,
   stuck frames or flicker?

**Pass:** the pattern check passes, and the reviewed clips match the spec.
Camera judgement is "looks right". Pixel accuracy comes from L2.

### L4: pipeline over USB

This checks the whole path, hook → app → device, without Bluetooth. That
matters because an agent can't launch the app with Bluetooth on.
`make e2e` (`tools/boopctl e2e [--writer none|apple]`) does all of it:

1. `tools/boopctl bridge --socket /tmp/boop-e2e/usb.sock` owns the serial
   port.
2. The app starts headless with isolated state and its own hook socket,
   never the everyday ones:
   `Boop --headless --state-dir /tmp/boop-e2e/state --link usb:/tmp/boop-e2e/usb.sock --socket /tmp/boop-e2e/boop.sock --classifier rules --writer none --name Pip --trace --debug-log /tmp/boop-e2e/brain.jsonl`.
   The rules always classify and no writer is the default, so runs repeat;
   `--writer apple` runs the same fixtures with Apple's model writing the
   words.
3. The fixtures in `app/Tests/Fixtures/hooks/e2e/` (a Claude session, a
   Codex approval answered within 2 s, one left for 10 s) go through the
   real `boop-hook`. Besides payloads they hold checkpoints: `expect` (poll
   `dbg.state` until it matches, within `within_ms`, 2000 by default),
   `expect_not` (it mustn't match for `for_ms`, or until `until_ms` after
   the last hook), `wait_ms`, `advance_ms` (move the app's clock, for a long
   turn) and `shot` on an `expect` line (a screenshot).
4. Latency is from launching `boop-hook` to the board's `rx.state` count
   going up, on the host clock. A hook that changes nothing sends no
   `state`, and is left out.
5. Afterwards: the Happened lines in the memory files, the topics, error
   class and finishes in the brain's inputs, no `PRIVATE_` marker from the
   fixtures in any app file or the brain's log, and, from the `--trace`
   log, that every brain moment came after the rules' reaction and didn't
   start while a rule moment was playing.

`boopdev replay <fixture>` without `--socket` runs the same fixtures on the
virtual clock and prints what the core decides; it skips the checkpoints.

**Pass:** every checkpoint matches, and hook-to-device-state latency is
under 200 ms at p95.

### L5: brain

1. `boopdev brain --classifier rules --writer apple --inputs app/Tests/Fixtures/inputs --memory app/Tests/Fixtures/memory`
   (all four are the defaults, from the repo root) runs the real pipeline
   on recorded inputs: agents starting and finishing, things said to Boop,
   and new days. They run 3 minutes apart in file order (`--gap-min`) and
   share one transcript, so its window fills and moves on as it would in
   the app ([HARNESS.md](HARNESS.md) §4). Every input gets a fresh copy of
   the sample memory. `--classifier jev` runs the same with Jev, its key in
   `BOOP_JEV_KEY`. `--print` shows each input and what ran, and every pass
   is logged to `/tmp/boop-brain/<classifier>-<writer>.jsonl` (`--out`).
2. It reports: refusals (a model's guardrail declining), how many inputs
   Stage 1 answered on the menu, what each kind of input decided, the
   writer's slots filled and its failures, the calls handed to actions and
   those they dropped and why, the window's largest size and its restarts,
   and, for each kind of input, each stage's p50 latency and the p95 of the
   two together against its deadline.
3. The agent reads a sample of about 20 passes against `steering.md`: are
   the decisions in character and never nagging, the words right for what
   happened, and the memory lines worth keeping?

**Pass:** Stage 1 answered on the menu, in time, for every input it didn't
refuse, fewer than 5% of the calls handed to actions were dropped by them,
every kind's p95 is under its deadline, and a reviewed sample. Refusals are
reported, not failed: a refused pass leaves Boop with the rules' reaction,
and a refused write leaves the words empty. Apple's model is available on
this Mac with an 8K context.

### L6: the owner (morning)

These can't be checked without a person: Bluetooth connection (launching
the app with Bluetooth), the mic and speech recognition, real touches and
touch calibration, sound (by ear, with `boopctl mumble`, `say`, `volume` and `sound`), real Claude Code and
Codex sessions with installed hooks, the Mac app in the real menu bar, and
how Boop feels. They're on the
morning checklist in [PLAN.md](PLAN.md).

## 6. Webcam rules

The webcam stays opt-in ([CLAUDE.md](../CLAUDE.md)). A run may use it only
when its prompt authorises it and the owner has positioned the board. The
authorisation covers that run only. [LOOP.md](LOOP.md) authorised it for
the v1 build until the owner withdrew that on 2026-09-26, so the webcam is
off for the rest of that run.

- Clips are bounded: at most 10 s each, video only, no audio.
- Raw recordings stay in `/tmp` and are deleted at the end of the run. Only
  cropped frames chosen as evidence go into the repo.
- The Mac is kept awake with `caffeinate`, and the lid stays open.
- If the framing check fails, don't try to fix it. Skip L3 and report it.

## 7. Evidence

Each milestone writes `plan/evidence/v1-build/<milestone>/README.md`: what ran,
the result, anything accepted or changed and why, plus a few small PNGs
(simulator, device screenshot, webcam crop). Logs and raw video stay in
`/tmp`. A build run also keeps a running log and ends with a report
([PLAN.md](PLAN.md) §5).
