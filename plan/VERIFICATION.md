# Boop: verification

Updated 2026-09-25. How we check that Boop works, especially what's on its
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
| L5 Brain | Does the brain behave on real triggers? | Apple's on-device model |
| L6 Person | Bluetooth, mic, touch accuracy, sound, real agents | The owner, in the morning |

## 2. The tools

| Tool | What it is |
| --- | --- |
| `make test` | Swift unit tests. There's no Xcode here, so this runs the XCTest shim: `python3 app/tools/test.py`, which runs `swift run BoopTests` |
| `make fw-test` | Firmware unit tests on the Mac: `pio test -e native` |
| `make sim` / `tools/boopctl sim` | The simulator. It builds the same drawing and behaviour code as the firmware for the Mac, runs a scenario, and writes PNGs |
| `tools/boopctl` | The new device tool, replacing `buddyctl.py`. It's Python in `tools/.venv` (pyserial, Pillow), created by `make tools` |
| `tools/boopctl bridge` | Owns the USB serial port and shares it through a Unix socket, so the Mac app and other `boopctl` commands can use the board at the same time |
| `tools/webcam/webcam.sh` | The existing AVFoundation recorder and frame extractor. `boopctl cam …` wraps it |
| `boopdev` | A Swift CLI in the app package for replaying hooks, running the harness on recorded triggers, and printing the memory files. `boopdev replay <fixture>` alone runs the payloads through the hook's field picking, the adapter and the core on a virtual clock and prints every decision (`--states` for snapshots only); with `--socket` it sends them through the real `boop-hook` to a running app |

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
| `shot --out x.png` | Screenshot the device's canvas |
| `diff a.png b.png` | Pixel diff. Exits non-zero past a threshold and writes a highlighted diff image |
| `expect '<json>' [--timeout S]` | Poll `dbg.state` until it matches, or fail |
| `press tap\|hold [--ms N]` | Inject a BOOT press |
| `touch X Y [--ms N]` | Inject a touch at screen coordinates |
| `clock freeze T \| step MS \| run` | Control the device clock for repeatable frames |
| `pattern` | Show the bring-up test pattern |
| `perf --seconds N [--motion]` | Sample fps and heap over time; `--motion` plays moments back to back so every sample is mid-motion |
| `soak --minutes N` | Random, realistic traffic and inputs (with one 35 s silence), then check for resets, a drifting heap minimum, and that calm snapshots bring back the plain face |
| `cam frame\|pattern\|clip <name>` | Webcam helpers (L3 in §5). Clips are live presets: `idle`, `needs_you`, `cheer`, `ladder` (sped-up clock), `cheers` (sizes 1–3) and `tap` |
| `calibrate` | Touch calibration. Needs a person to tap 4 targets |

## 3. The debug channel

Over USB, the firmware accepts every normal protocol message
([PROTOCOL.md](PROTOCOL.md)) plus debug messages whose type starts with
`dbg.`. Debug messages are ignored over Bluetooth.

| Message | Reply |
| --- | --- |
| `{"t":"dbg.ping"}` | `{"t":"dbg.ping","fw":…,"sha":…,"up":ms,"heap":…,"heap_min":…,"fps":…,"link":"usb\|ble\|none","ble":"off\|adv\|conn","name":"Boop-XXXX"}`. `ble` is Bluetooth's state (advertising or connected) and `name` the advertised name |
| `{"t":"dbg.state"}` | `{"t":"dbg.state","screen":"face\|needs_you\|threads\|stats\|no_app\|pattern","base":…,"attn":…,"rung":0-3,"moment":{"anim":…,"left_ms":…},"quiet":…,"focus":…,"led":"#RRGGBB","audio":{"playing":…,"syllables":…},"last_input":…}` |
| `{"t":"dbg.shot"}` | A header line `{"t":"dbg.shot","w":240,"h":320,"bytes":N,"crc":…}`, then one line of base64: 512 bytes of RGB565 palette (256 little-endian entries) followed by 76,800 bytes of pixel indexes, row by row. `crc` is the CRC-32 (as zlib's) of those bytes |
| `{"t":"dbg.clock","freeze":T}` / `{"step":MS}` / `{"run":true}` | Freeze the clock at T (which also seeds randomness from T), step it, or let it run |
| `{"t":"dbg.press","ms":N}` / `{"t":"dbg.touch","x":…,"y":…,"ms":N}` | Inject input through the same code path as real input |
| `{"t":"dbg.pattern"}` / `{"fill":N}` | Show the test pattern, or a solid screen of palette index N, until the next `state` |
| `{"t":"dbg.light","bl":0-255,"led":"#RRGGBB"}` | Set the backlight and the RGB LED (both optional), for bring-up and webcam framing |
| `{"t":"dbg.reset"}` | Forget everything the Mac has said, the moment and the local screen, and freeze the clock at 0. Every scenario starts with it |

At 460800 baud a screenshot takes about 2.3 s. `dbg.ping` also reports
`draw_us` and `push_us`, the last frame's drawing and pushing time.
`dbg.state` also carries the behaviour's own view: `hushed` (tapped during
needs you), `life` (the idle-life event showing: `blink`, `glance`, `peek`,
`bob`, `rumble` or null), `night`, `hungry`, and `sfx`, the last sound cue
with its time (`chirp`, `jingle` or `pulse`, for F5's player and for tests
while there's no speaker). `audio.playing` is true while the mouth follows a
mumble. `dbg.state` also carries bring-up readings: `clock` (`now`, `frozen`), `boot` (BOOT's level), `touch`
(`down`, `irq`, `raw` as x, y, z), `bat` in mV, `amp` and `bl`.

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
{"t":"state","base":"working","busy":1,"idle":0,"wait":0,"mood":{"energy":100,"pace":100,"pitch":100},"threads":[["claude","jetpack","work"]]}
{"clock": 800}
{"shot": "working"}
{"t":"moment","anim":"cheer","size":3,"ttl":5}
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
| `{"input": …}` | Inject a press or touch |
| `{"shot": "name"}` | Save a picture as `name.png` |
| `{"expect": {…}}` | Compare with `dbg.state`; fail on mismatch. Only the keys given are compared, recursively |

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
  §3 has tests. That covers adapter mapping, core rules (screen priority, XP,
  hunger, mood, quiet), each action's own checks, Voice (dialect,
  determinism, the English check), memory limits and snapshots, the harness
  with a fake brain (shape check, one call at a time, `talk` cancelling), and
  device link message encoding.
- **Firmware (`make fw-test`):** the protocol parser, line reassembly across
  BLE packets, the behaviour state machine (screen priority, nudge ladder
  timing, moment expiry, the 30 s no-app timeout), input gestures, and
  canvas primitives.

**Pass:** everything green. New code comes with tests.

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
   may lie flat in landscape, with USB-C to the right in the camera's view.
   Rotate the crop so USB-C is at the bottom before judging orientation.
2. **Pattern** (bring-up): `boopctl cam pattern` shows the test pattern,
   captures it, and samples the colour blocks. It checks that red reads as
   red (not blue, which would mean BGR order), that white is bright and
   black is dark (not inverted), and that the UP arrow is at the top away
   from USB-C (rotation). Fix the panel settings in the firmware until it
   passes, then record them in [DEVICE.md](DEVICE.md) §4.
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

1. `tools/boopctl bridge` owns the serial port.
2. Start the app headless with isolated state:
   `Boop --headless --state-dir /tmp/boop-e2e --link usb:/tmp/boop-e2e/usb.sock`.
   It uses its own hook socket and memory files, never the everyday ones.
3. `boopdev replay app/Tests/Fixtures/hooks/<session>.jsonl --socket /tmp/boop-e2e/boop.sock`
   sends recorded hook payloads through the real `boop-hook` binary.
4. `boopctl expect` polls `dbg.state` and screenshots at each checkpoint,
   for example: working → needs you (immediately for Claude, after the grace
   period for Codex) → working → cheer.
5. The app's own log and `boopdev memory --state-dir …` confirm the memory
   files and XP changed as the spec says.

**Pass:** every checkpoint matches, and hook-to-device-state latency is
under 200 ms at p95 (host clock, measured by `boopdev replay`).

### L5: brain

1. `boopdev brain --brain apple --triggers app/Tests/Fixtures/triggers/ --memory app/Tests/Fixtures/memory/`
   runs the real harness and Apple's on-device model on recorded triggers.
2. It reports: answers with valid shape (target 100%), tool calls each
   action dropped and why, the silence rate, and latency p50/p95.
3. The agent reads a sample of about 20 answers against `steering.md`. Is
   it in character, never nagging, and the right word when there is one?

**Pass:** 100% valid shape, fewer than 5% of tool calls dropped, p95 under
the trigger deadline, and a reviewed sample. Apple's model is available on
this Mac with an 8K context.

### L6: the owner (morning)

These can't be checked without a person: Bluetooth connection (launching
the app with Bluetooth), the mic and speech recognition, real touches and
touch calibration, sound (when a speaker is attached), real Claude Code and
Codex sessions with installed hooks, and how Boop feels. They're on the
morning checklist in [PLAN.md](PLAN.md).

## 6. Webcam rules

The webcam stays opt-in ([CLAUDE.md](../CLAUDE.md)). A run may use it only
when its prompt authorises it, as [LOOP.md](LOOP.md) does for the v1
build, and the owner has positioned the board. The authorisation covers
that run only.

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
