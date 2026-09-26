# Boop: plan

Updated 2026-09-26. The build order for v1, the check that closes each
milestone, how the unattended build runs, the owner's morning checklist,
the later port to ESP-IDF + LVGL, and the open items (§7). The specs are
listed in [README.md](README.md); ideas that aren't in v1 are in
[FUTURE.md](FUTURE.md), so don't build them. [VERIFICATION.md](VERIFICATION.md)
defines the checks (L0–L6).

## 1. Starting point

**The build started from** the previous generation: `app/` (a Swift
menu-bar app), `firmware/esp32/` (firmware for a different board), their
tools, and the older generation in `archived/`. v1 **rewrote everything**,
and the v1 code has replaced it. The tag `gen2-final` keeps the previous
generation one command away (`git show gen2-final:<path>`). What's left
under `archived/` is history (research, docs and the gen-2 specs in
`archived/plan-gen2/`), plus a few evidence scripts there and the gen-2
case model in `archived/hardware/case/`. Keep `landing/` (the live landing
page) and the specs.

Old code was reused only where it fit the new architecture as is. The
table is kept as a record:

| Worth reusing | Where it goes |
| --- | --- |
| `HookInstaller.swift`: safe merging into `~/.claude/settings.json` and `~/.codex/hooks.json` | The installer |
| `BoopSignal/`: the compiled hook client (then HTTP) | `boop-hook`, rewritten for the Unix socket |
| `BLEManager.swift`: the CoreBluetooth Nordic UART central | Device link: Bluetooth |
| `VoiceRuntime.swift`: Foundation Models session setup | Brains: Apple |
| `app/Boop/Views/ViewState.swift`: the `SwiftUI.State` alias | The app shell (see below) |
| `app/Tests/Fixtures/hooks/`: recorded real hook payloads | Adapter tests and end-to-end fixtures |
| `app/TestSupport/XCTestShim`, `app/tools/gen-test-runner.py` | Tests without Xcode |
| `InstanceLock.swift` and the isolated-instance idea | `--headless` mode |
| `buddyctl.py`: serial locking, framing, the PNG writer | `tools/boopctl` |
| `tools/webcam/` | Kept as is |

**Environment facts** (checked 2026-09-25):

- **Toolchain:** macOS 27 with Command Line Tools only, no Xcode. Swift
  tests run through the XCTest shim via `make test`.
- **Swift macros that are missing** (their plugins aren't in Command Line
  Tools, so they fail to compile):
  - SwiftUI's `@State`. Use the `ViewState` alias
    (`typealias ViewState<Value> = SwiftUI.State<Value>`) and write
    `@ViewState`.
  - Foundation Models' `@Generable` and `@Guide`. Build the answer schema at
    runtime with `DynamicGenerationSchema` →
    `GenerationSchema(root:dependencies:)` →
    `session.respond(to:schema:)`, and read `GeneratedContent`. This route
    was tested here, and a tap trigger answered in 1.3 s.
- **Apple's model:** available from the shell, with an 8K context.
- **Firmware tools:** PlatformIO is `/opt/homebrew/bin/pio`.
  `firmware/tools/pio.sh` keeps PlatformIO's core in
  `firmware/.platformio-core/` (one per checkout, git-ignored), so esptool
  is `firmware/.platformio-core/penv/bin/esptool` once `make fw` has run.
  There's 210 GB of disk free for toolchains.
- **Board:** on `/dev/cu.usbserial-110` (the number can change). It's an
  ESP32-D0WD-V3 with 4 MB flash, behind a CH340 USB bridge that tops out at
  460800 baud with macOS's driver. Auto-reset works.
- **Camera:** "MacBook Air Camera", id `6C707041-05AC-0010-000D-000000000001`.
- **Python:** system `python3` (3.14) has no pyserial or Pillow. `make tools`
  creates `tools/.venv` with both (tested).
- **Bluetooth:** an agent can't launch the app with Bluetooth on, or run
  `bleak`; macOS kills the process. USB serial works.
- **Old hooks:** the previous generation's hooks are still installed. They
  call `~/.boop/boop-hook.sh` from `~/.claude/settings.json` and
  `~/.codex/hooks.json`. They fail open, so they're harmless during the
  build. The new installer removes them.

## 2. Target layout

```
app/                       Swift package
  BoopKit/                 library: Adapters, Core, Harness, Brains, Actions,
                           Voice, Memory, DeviceLink, App, Install
  Boop/                    the menu-bar app (also runs --headless), and
                           Talk.swift (push-to-talk)
  BoopHook/                boop-hook, the hook client
  HookWire/                what boop-hook and the app share: the hook line,
                           topic tags, the socket (Foundation only)
  BoopDev/                 boopdev: replay, memory, voice, brain, talk, hooks
  Tests/                   unit tests, plus Fixtures/{hooks,triggers,memory}
  TestSupport/             the XCTest shim (there's no Xcode)
  tools/                   test.py and gen-test-runner.py, for make test
firmware/                  PlatformIO project
  platformio.ini           envs: cyd24 (the board), native (Mac: tests + simulator)
  src/main.cpp             the board's entry point, with USB serial
  src/board/               pins, LovyanGFX config, button, touch, LED, DAC, battery
  src/render/              8-bit canvas, palette, fonts, face, screens (pure C++)
  src/app/                 protocol parser, behaviour state machine, gestures,
                           touch map, and the debug channel in device.cpp
                           (pure C++)
  src/link/                the BLE transport (ble.cpp)
  src/voice/               syllable player
  src/sim/                 boop-sim, the simulator's entry point
  assets/                  generated fonts and voice samples (checked in)
  test/                    unit tests, scenarios/, golden/
  tools/                   pio.sh (PlatformIO inside the checkout), version.py
tools/
  boopctl                  device tool (runs tools/.venv; code in boopctl_lib/)
  voicegen/                builds the voice assets
  fontgen/                 builds the fonts
  webcam/                  existing recorder
  build-loop.sh            runs the unattended build (§5)
Makefile                   build run test tools fw flash sim fw-test e2e
                           webcam webcam-test clean
```

`plan/steering.md` is the single source for steering. The build copies it
into the app's resources, and a unit test fails if the copies differ.

## 3. Rules for the build

1. **Branch and commits.** Work on branch `v1-overnight`. M0 creates it and
   tags the starting commit `gen2-final`. Commit whenever tests pass, and at
   least every 30 minutes (`WIP F2: face renderer`). Close each milestone with
   `F2: renderer and simulator — <one line>`. Never commit failing tests
   outside a WIP commit.
2. **Specs are the contract.** If the implementation has to differ, change
   the spec in the same commit and add a row to the decision log
   ([ARCHITECTURE.md](ARCHITECTURE.md) §11).
3. **Don't touch the owner's setup.** Never modify `~/.claude`, `~/.codex`,
   `~/.boop` or the everyday app's state. Tests use a temporary `HOME` and
   isolated state directories.
4. **No Bluetooth from the agent.** Don't launch the app with Bluetooth and
   don't run `bleak`. Anything live goes over USB, through `boopctl bridge`.
5. **Webcam:** authorised for this build run only
   ([VERIFICATION.md](VERIFICATION.md) §6). The owner positions the board
   before starting. On 2026-09-26 the owner switched it off for the rest
   of the v1 run: skip L3 checks and say so.
6. **Don't get stuck.** If one problem takes about 45 minutes, record it
   (what failed, what was tried, the best guess), mark the milestone
   Blocked, and move to the next milestone that doesn't depend on it.
7. **One thing at a time.** Iterations run strictly one after another, and
   each works on one milestone. No parallel agents, subagents or extra
   worktrees.
8. **Keep the checks honest.** Only report a check as passed if it ran and
   passed. If a check was skipped or changed, say so and why.
9. **Leave the board clean.** At the end, flash the final firmware and leave
   it on the idle face, or on the test pattern if bring-up failed.

## 4. Milestones

Order: **M0 → F1 → F2 → F3 → F4 → A1 → A2 → A3 → A4 → J1 → F5 → J2 → J3.**
Bluetooth (F4) comes before the app track so the morning test can use it.
Sound (F5) comes late because there's no speaker to hear it. F6, A5 and A6
came after the build, at the owner's request.

Statuses are Not started, In progress, Passed, or Blocked (with the reason).

| # | Milestone | Status |
| --- | --- | --- |
| M0 | Setup | Passed |
| F1 | Board bring-up | Passed |
| F2 | Renderer and simulator | Passed |
| F3 | Device behaviour | Passed |
| F4 | Bluetooth on the device | Passed |
| A1 | App core: adapters, hook client, core rules | Passed |
| A2 | Memory, Voice, actions | Passed |
| A3 | Harness and brains | Passed (under the owner's 2026-09-26 ruling; known issues in `A3/README.md`) |
| A4 | Device link, app shell, push-to-talk, installer | Passed |
| J1 | End to end over USB | Passed |
| F5 | Voice on the device | Passed |
| J2 | Soak and polish | Passed |
| J3 | Handoff | Passed |
| F6 | Landscape and cuter eyes | In progress: code, L0, L1 and L2 pass. The board runs the landscape build, its 83 screenshots in 11 scenarios match the simulator pixel for pixel, and `perf --motion` gives at least 49 fps (50 over 30 s, 49 over 60 s) with 72.7 KB free. Only the owner's look (orientation and liking the face) and touch calibration remain (morning checklist rows 2–3). [Evidence](evidence/v1-build/F6/README.md) |
| A5 | Mac app look and flow | In progress: code, L0 and the app's snapshot check pass (light and dark). Only the owner's look in the real menu bar remains (morning checklist rows 5 and 7). [Evidence](evidence/v1-build/A5/README.md) |
| A6 | Brain conversation | In progress: code and L0 pass. L5 with Apple's model: the `say` limit line holds, but with history the brain answers quiet far more often, and it calls `note` on most events ([evidence](evidence/2026-09-26-brain-conversation/README.md)). Tuning the behaviour is next |
| P1 | Port to ESP-IDF + LVGL (later, gated) | Not started |

### M0: Setup

- Tag `gen2-final`, then create branch `v1-overnight`.
- Delete `firmware/esp32/` and whatever else v1 won't use. Create the new
  PlatformIO project in `firmware/` with envs `cyd24` and `native`. A wrapper
  keeps PlatformIO's packages inside the checkout, as `pio_ws.sh` did.
- Restructure `app/` into the target layout. Remove the old sources and the
  `wire`/Hummingbird dependencies, but keep the XCTest shim working.
- Create `tools/boopctl` and `make tools` (a venv with pyserial and Pillow).
- Makefile targets: `build run test tools fw flash sim fw-test e2e`.
- Update CLAUDE.md and AGENTS.md if the commands differ from what was built.

**Done when:** `make build`, `make test` (at least one test), `make fw`,
`make fw-test` and `make tools` all succeed, and `tools/boopctl ports` lists
the board.

### F1: Board bring-up

- **Drivers:** LovyanGFX config ([DEVICE.md](DEVICE.md) §4), with the screen
  on SPI2, touch on SPI3, and a PWM backlight.
- **Canvas:** the 8-bit canvas, allocated first, pushing only the rows that
  changed.
- **Test pattern:** 6 large colour blocks (red, green, blue, white, black,
  amber), labelled corners, and a big UP arrow. Since F6, also a black bar
  down the USB-C edge.
- **USB link:** 460800 baud, with `dbg.ping`, `dbg.state`, `dbg.shot`,
  `dbg.clock`, `dbg.pattern`, `dbg.press` and `dbg.touch`.
- **BOOT:** shorter than 400 ms is a tap; 400 ms or more is push-to-talk
  until release.
- **Other hardware:** RGB LED with PWM, the amp off by default, battery ADC,
  and raw touch readings.
- **Simulator start:** the `native` env builds the canvas and the pattern,
  so the simulator can already render it.

**Done when:**

- L2: `ping` works and shows at least 150 KB free heap before Bluetooth.
- L2: the device's screenshot of the pattern is identical to the
  simulator's.
- L3: the webcam pattern check passes, and the confirmed panel settings are
  written into [DEVICE.md](DEVICE.md) §4.
- Injected presses and touches show up in `dbg.state`. Physical presses are
  checked in the morning.

### F2: Renderer and simulator

- **Palette:** "Warm Terminal", meaning a black-glass background, light oat
  eyes and one amber accent, plus a few state colours (a warm glow for
  cheers, a dim red for oops). Keep it in one header.
- **Fonts:** two sizes, printable ASCII.
- **Face:** eye openness, where the eyes look, upper and lower lids, squash
  and stretch, and mouth curve and opening. Blends are eased and interruptible,
  150 ms or less.
- **Screens:** face, needs you, threads, stats, no app, and the status strip
  with its icons ([UX.md](UX.md) §2–3). The bubble shows the one real word
  in amber, with squiggles.
- **Simulator:** `boop-sim` runs a scenario and writes PNGs via
  `boopctl sim`.
- **Goldens:** one for every screen and state in [UX.md](UX.md) and
  [BEHAVIORS.md](BEHAVIORS.md).

**Done when:**

- L0: canvas and face tests pass.
- L1: every golden has been looked at and accepted.
- L2: device screenshots are identical for every scenario, with at least
  25 fps during blends.
- L3: clips of the idle, needs-you and cheer screens are reviewed.

### F3: Device behaviour

- **Protocol:** parse `state` and `moment` ([PROTOCOL.md](PROTOCOL.md)).
- **Base states:** asleep, idle and working, with intensity from the busy
  count.
- **Idle life:** blinks every 2–6 s, glances, small self-amusements, shaped
  by mood.
- **Needs you:** the ladder is look, then chirp and lean at 45 s, then buzz
  at 2 min (three amber light pulses on this board). Focus mode makes it
  visual only.
- **Moments:** the animation set, with sizes and time-to-live. A new moment
  replaces a playing one, and the mouth syncs to `say` even without audio.
- **Inputs:** the gestures in [UX.md](UX.md) §4, with feedback within 20 ms
  and `input` messages to the Mac (including `focus`).
- **Everything else:** quiet, screen cycling, threads and stats, the no-app
  screen after 30 s of silence, night dimming, hunger (tummy rumble), and the
  status strip icons.

**Done when:**

- L0: state-machine tests pass, including every timing.
- L1: every row of [BEHAVIORS.md](BEHAVIORS.md) §3 has a reviewed golden.
- L2: the scenario suite passes every `expect`, and screenshots are
  identical.
- Soak: 20 minutes with no reset.
- L3: clips of the needs-you ladder (with a sped-up clock), cheers at each
  size, and a tap wiggle are reviewed.

### F4: Bluetooth on the device

- NimBLE Nordic UART peripheral named `Boop-XXXX`, with no security.
- Line reassembly across packets, and the same dispatch as USB.
- `status` every 60 s, and `input` sent out.
- Release Classic Bluetooth memory. The canvas is still allocated before
  Bluetooth starts.

**Done when:**

- L0: reassembly tests pass.
- L2: `ping` shows it advertising, with minimum free heap at least 60 KB and
  Bluetooth on.
- Performance is unchanged, and the soak passes with Bluetooth on.
- A real connection is checked in the morning.

### A1: App core

- **Adapters:** the Claude and Codex mappings and topic tags
  ([ADAPTERS.md](ADAPTERS.md) §3), with project names from `cwd`.
- **Hook client:** `boop-hook` on the Unix socket, with a 50 ms connect
  timeout and a 256 KB input cap. It never prints and always exits 0. The
  app side is the socket server.
- **Core:**
  - **Sessions:** the session table, and the "needs you" rules (start,
    clear, the 2 s Codex grace period, the 10-minute safety net).
  - **Screen:** screen priority and the `state` snapshot builder.
  - **Rules:** XP, levels, days together and hunger
    ([BEHAVIORS.md](BEHAVIORS.md) §4), mood, working chatter, and quiet,
    focus and away.
  - **Triggers:** 3 s merging and the core's gates.

**Done when:**

- L0: mapping and topic tests pass on the recorded fixtures.
- `boop-hook` exits in under 50 ms when the app isn't running.
- Core rule tests pass for every row of [BEHAVIORS.md](BEHAVIORS.md) §3.1–3.2
  and §4.
- `boopdev replay` on a fixture prints the expected `state` snapshots.

### A2: Memory, Voice and actions

- **Memory store:** the three files and their formats
  ([ARCHITECTURE.md](ARCHITECTURE.md) §4), with limits, atomic writes and
  snapshots to `history/`. A file that won't parse is restored. The first
  activity of a new day runs `reflect`, then starts short-term fresh.
- **Voice:** the syllable set, the dialect from the seed, the feelings, tune
  and tempo, and the English check ([VOICE.md](VOICE.md) §3–7). Up to 5
  retries, then the safe hum.
- **Actions:** `say`, `face`, `quiet`, `note`, `remember`, `forget`,
  `temperament` and `moment`. Each owns its tool definition and its checks.

**Done when:**

- L0: every memory limit is enforced, and snapshots and restore work.
- Voice is deterministic, and a property test of 10,000 lines finds zero
  dictionary hits.
- Every action drops invalid input and logs why.

### A3: Harness and brains

- **Harness** ([HARNESS.md](HARNESS.md) §3): the tool registry, one call at
  a time with replace and cancel, the prompt builder with its budgets, the
  shape check, dispatch, and the debug log.
- **Brains:**
  - **Apple:** a runtime schema, as in §1, with enums constrained and up to
    3 calls.
  - **Rules only:** reads the fallback table in `steering.md`.
  - **Cloud:** interface only, left disabled.
- **Fixtures:** at least 50 triggers covering every trigger type, plus a
  sample `long-term.md` and `short-term.md`, in `app/Tests/Fixtures/`.

**Done when:**

- L0: harness tests with a fake brain pass (shape rejection, cancel,
  replace, at most 3 calls).
- L5: the brain run on the fixtures passes, and its sample is reviewed.

### A4: Device link, app shell, push-to-talk and installer

- **Device link:**
  - **Bluetooth central:** scans for `Boop-*`, connects, sends `state` on
    change and every 10 s, receives `input` and `status`, and reconnects.
  - **USB transport:** through the bridge socket.
- **App shell:**
  - **Menu bar:** the icon (dot or amber) and the popover
    ([UX.md](UX.md) §7).
  - **Settings:** name and sweet-or-cheeky (asked once at setup), the brain
    choice and API key (Keychain; the cloud brain is shown as not yet
    available), hooks, and device status.
  - **Headless mode:** `--headless --state-dir --link --socket`.
- **Push-to-talk:** `talk_on` starts the Mac mic with on-device speech
  recognition (the Speech framework). `talk_off` sends a `talk` trigger.
  Info.plist carries the usage descriptions. `boopdev talk "<words>"`
  injects a transcript for tests.
- **Installer:** install, repair and remove Boop's entries in
  `~/.claude/settings.json` and `~/.codex/hooks.json`. It also removes the
  previous generation's entries, which call `~/.boop/boop-hook.sh`, and
  leaves everything else alone.
- **Doctor:** rewrite `skills/doctor/doctor.sh` for the new socket.

**Done when:**

- L0: installer tests on a temporary `HOME` pass. They're idempotent, keep
  other hooks, and remove old and current Boop entries only.
- Device-link encoding tests pass.
- The app builds, and headless mode starts and stops cleanly.

### J1: End to end over USB

- **Fixtures:**
  - a Claude session: prompt, tools with topics, `PermissionRequest`,
    activity, a long `Stop`, and a `StopFailure`;
  - Codex requests: one resolved within 2 s (no "needs you") and one after
    10 s ("needs you" appears at 2 s).
- **Run:** the headless app, the bridge and replay
  ([VERIFICATION.md](VERIFICATION.md) L4).

**Done when:**

- L4 passes: every checkpoint matches, with p95 latency under 200 ms.
- The memory files and XP change as specified.
- The brain's moments arrive after the rule reactions.
- L3: a webcam clip of a full Claude session is reviewed.

### F5: Voice on the device

- **Voice assets:** `tools/voicegen` synthesises about 60 syllables and 40
  words ([VOICE.md](VOICE.md)): macOS `say` → `afconvert` → pitched up and
  normalised → 8-bit samples at 11.025 kHz → `firmware/assets/voice.h`.
- **Player:** enables the amp, runs the continuous DAC at 22.05 kHz, and
  resamples for pitch and tempo. It follows volume, focus, quiet and mute.

**Done when:**

- L0: resampler tests pass.
- L2: the audio timeline in `dbg.state` matches `say` (syllable count, and
  duration within 10%).
- The firmware fits its app slot with at least 15% to spare.
- Hearing it waits for a speaker.

### J2: Soak and polish

**Done when:**

- A 30-minute soak with replayed traffic and the Apple brain shows no
  resets, leaks or stuck states.
- All tests are green and all goldens reviewed.
- `README.md` describes the new product and commands.

### J3: Handoff

- Write `plan/evidence/v1-build/REPORT.md`. It covers each milestone (passed,
  blocked or skipped, with evidence links), known issues, anything the
  morning checklist should do differently, and the confirmed panel settings.
- Flash the final firmware and leave the board on the idle face.
- Update the status table, create `plan/evidence/v1-build/DONE`, and commit.

### F6: Landscape and cuter eyes

Two changes to the look, asked for by the owner after the build
([UX.md](UX.md) §2). Boop sits sideways, so the screen is landscape,
320×240, with USB-C on the right. And the v1 eyes were "too realistic, not
cute enough": cream eyes with a dark pupil and a highlight read as real
eyeballs, and the gen-2 face, with solid eyes, was cuter.

- **Canvas and panel:** `render::kWidth` 320, `kHeight` 240, still 76.8 KB.
  The panel stays configured as its physical 240×320 and LovyanGFX turns
  it (`firmware/src/board/display.h` `kRotation` 1, or 3 if that's upside
  down), so rows still stream in order with no per-pixel cost. Push bands
  of 12 rows keep the buffers at 2 × 7.68 KB ([DEVICE.md](DEVICE.md) §4,
  §6).
- **Touch:** the default map is the raw range turned with `kRotation`
  (`firmware/src/app/touch_cal.h`, pure C++). A stored calibration carries
  the screen size and rotation it was fitted on and is ignored otherwise;
  the portrait build's NVS record is deleted. `boopctl calibrate` places
  its crosses from the size in `dbg.ping`.
- **Layout:** the strip is the bottom 36 px, the bubble the 60 px above it.
  The face is centred in the 204 px above the strip, and with a bubble it
  eases up into the top 144 px at 75%. Needs you, threads (one row per
  session with an agent column), stats (the ring on the left), the starving
  bowl, the strip and the test pattern (with a black bar down the USB-C
  edge) are laid out for the wide screen.
- **Eyes:** solid rounded rectangles in the eye ink (60 × 80 px, corner
  radius 22, centres 134 px apart), with no pupil, iris or highlight. A
  look moves the whole eye (26 px sideways, 16 px up or down); the eye on
  the side being looked towards grows by up to 11% and the other shrinks,
  and the mouth follows by 45%. Wherever a lid meets the edge of an eye
  the corner is rounded (8 px, or the largest radius down to 2 px that fits
  a nearly shut eye), and happy eyes are crescents.
- **Pose:** `Pose::pupil` is now `Pose::eyeSize`: both eyes a little bigger
  (curious, listening, needs you, love, startled) or smaller (worried,
  busy), without the mouth. Thinking lifts the whole face and keeps the eye
  tops round rather than lidding them, so it isn't the working face
  mirrored.
- **Mouth:** a little smaller (28 px wide) and tucked in closer under the
  eyes. An open mouth is a rounded bowl.
- **Tools:** screenshots take their size from the `dbg.shot` header; a
  golden of another size counts as changed rather than crashing `boopctl
  sim`, and its diff image shows the two side by side; the webcam check
  turns the crop so USB-C is on the right.

**Done when:**

- L0: the firmware unit tests pass.
- L1: every golden has been regenerated, looked at and accepted.
- L2: with this build flashed (`make flash`; `boopctl ping` shows `"w": 320`),
  device screenshots are pixel-identical to the simulator for every
  scenario, and `perf --seconds 30 --motion` gives a minimum no worse than
  F2's 44 fps.
- The owner flashes it and likes the face on the board (morning checklist
  row 2), then sees the test pattern the right way up with the black bar on
  the USB-C side (or sets `kRotation` to 3) and calibrates touch again
  (row 3).

### A5: Mac app look and flow

Asked for by the owner after the build: the Mac app should be simple but
nice, elegant and cute. The setup window was jarring, the overview mixed
controls with debug data (the board's id), settings was a separate
window, and gen-2's styling and flow were better ([UX.md](UX.md) §6–7).

- **One popover:** setup and settings open inside it; no windows. Setup
  opens it once, on first launch, and is four steps (hello, name and
  nature, agents, wake up) whose progress survives closing the popover.
- **Overview only shows:** volume, focus and "I'm away" move to Settings;
  small reminders show when a mode is on. The board's id is gone; the
  header says only whether the body is connected.
- **The look:** gen-2's "Boop Cream" tokens and building blocks (cards,
  section labels, status chips, session rows with a coloured edge), a small
  copy of the device's face in the header and setup, and the eyes as the
  menu-bar icon.
- **Tools:** `Boop --snapshots DIR` renders every pane and the icons from
  fixtures ([VERIFICATION.md](VERIFICATION.md) §2).

**Done when:**

- L0: `make test` passes and the app builds.
- The snapshots have been looked at in both appearances against
  [UX.md](UX.md) §7.
- The owner runs the app and likes it (morning checklist rows 5 and 7).

### A6: Brain conversation

Asked for by the owner after the build: a running transcript for the brain,
modelled on pi and as simple as possible ([HARNESS.md](HARNESS.md) §4–5).

- **Conversation:** event, tap and talk calls send the system prompt, the
  earlier exchanges and the new message, in that order, so a provider's
  prompt cache can reuse each request's start. No compaction: it starts
  over when steering, memory or tools change, when it's full, or after a
  failed answer.
- **Static tools:** every conversation call is offered the same four tools.
  A tool past its limit is named in the prompt (`say limit: …`) and a call
  to it is dropped.
- **Tools:** `boopdev brain --history N` sets the conversation's size for L5.

**Done when:**

- L0: `make test` passes, with the conversation's rules pinned in tests.
- L5: the brain run on the fixtures passes with history, and its sample is
  reviewed. **Open:** Apple's model goes quiet with history (taps got no
  reaction in 8 of 8 with 4 earlier exchanges) and calls `note` on most
  events even with `note limit: only on talk`.

### P1: Port to ESP-IDF + LVGL (later)

**Gate:** only after the owner has run the morning checklist and confirmed
v1 works. Then port *everything*, including the tools and checks:

- **Project:** ESP-IDF, via PlatformIO `framework = espidf` or `idf.py`,
  with `esp_lcd` for the ST7789 and `esp_lcd_touch_xpt2046`, on separate SPI
  hosts as today.
- **Drawing:** LVGL 9 via `esp_lvgl_port`. Boop's canvas renderer stays,
  shown through an LVGL canvas. Screens that benefit from widgets (threads,
  stats) can move to LVGL.
- **The rest:** raw NimBLE Nordic UART, the continuous DAC, NVS, and the same
  USB debug channel with `dbg.shot`.
- **Tools:** `boopctl`, the scenarios, the goldens and the webcam checks
  stay the same, because the protocol doesn't change. If screens move to
  LVGL, the simulator adds LVGL's desktop build.

**Done when:**

- The whole L0–L4 suite passes against the ESP-IDF build unchanged.
- Screenshots match the Arduino goldens, or the differences are reviewed.
- Performance is the same or better, and the budgets in
  [DEVICE.md](DEVICE.md) are updated.

After P1: Secure Boot v2, flash encryption and Bluetooth bonding, as their
own milestone.

## 5. Running the build

The build runs unattended as a series of short **iterations**, each with a
fresh context. Each one reads the state from files, does the next piece of
work, verifies it, commits, and exits. [LOOP.md](LOOP.md) is the prompt for
one iteration.

**State lives in files, not in any conversation:**

| File | Holds |
| --- | --- |
| The status table (§4) | Where each milestone stands |
| `plan/evidence/v1-build/PROGRESS.md` | A running log: one entry per iteration, ending with the exact next step |
| `plan/evidence/v1-build/<milestone>/README.md` | Each milestone's evidence |
| `plan/evidence/v1-build/DONE` | Created at the end, which stops the loop |
| Git | Everything else, committed at least every 30 minutes |

**How to run it:**

- **Recommended:** `caffeinate -dimsu tools/build-loop.sh` from the repo
  root. It runs one fresh `claude -p` session at a time, waiting for each
  to finish before starting the next, in auto permission mode with no
  permission prompts. A lock stops a second copy from starting. It stops
  when `DONE` exists.
  Logs go to `/tmp/boop-build-loop/`.
- **Alternative:** in an interactive Claude Code session, run
  `/loop Follow plan/LOOP.md`. It works the same way, but one session
  accumulates context, and a usage limit can end the loop.

**Usage limits and other interruptions.** Every iteration is safe to cut
off at any point:

- **Usage limit:** the iteration dies, and `build-loop.sh` waits 15 minutes
  and tries again, for up to 8 hours. The next iteration finds any
  uncommitted work, checks it, and carries on. With a 5-hour window that
  resets partway through the night, the build simply pauses and resumes.
- **A crash, a hang, or a reboot of the board:** the same. The next iteration
  reads `PROGRESS.md`, kills leftover bridges or headless apps, and
  continues.
- **No progress:** if three iterations in a row end without a new commit,
  `build-loop.sh` stops rather than burning usage.
- **Permission denials:** auto mode may refuse some actions, and nothing
  prompts. The iteration should find another way (for example, `git rm`
  rather than `rm -rf`) and note it in `PROGRESS.md`.

**Before starting (owner):**

1. Plug the Mac into power, and keep the lid open.
2. Make sure the old Boop app isn't running, so nothing else talks to the
   board.
3. Put the board facing the MacBook camera: the whole screen visible, about
   30–40 cm away, with even light and no glare.
4. Grant camera access once, and check the framing:
   `tools/webcam/webcam.sh record --camera 6C707041-05AC-0010-000D-000000000001 --seconds 3 --out /tmp/boop-framing`.
5. From the repo root, run `caffeinate -dimsu tools/build-loop.sh`.

## 6. Morning checklist (owner)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Read `plan/evidence/v1-build/REPORT.md` (or `PROGRESS.md` if it's still running) | What passed, what's blocked, and any changes to these steps |
| 2 | The board runs the landscape build (F6), flashed for its L2 check. Run `tools/boopctl ping`, and `make flash` first if it doesn't show `"w": 320`. Stand Boop sideways with USB-C on the right and look at it | `ping` shows `"w": 320` and `"h": 240`. The no-app face, landscape: sleepy solid eyes, a plug icon, dimmed, slow blinks. It becomes the idle face once the app connects (row 6). Whether the new eyes are cute enough is your call (F6); note anything that's off |
| 3 | Run `tools/boopctl pattern`. Then `tools/boopctl calibrate`: tap each amber cross (4 near the corners, then 1 in the middle) and lift. Do both only on the landscape build (row 2's `ping`): on the portrait build the pattern has no USB-C bar, and a calibration saved there is deleted when the landscape build starts | The UP arrow is at the top and the black bar is down the edge with the USB-C port. If the picture is upside down (the bar on the other side), set `kRotation` to 3 in `firmware/src/board/display.h`, `make flash`, and look again. Calibration prints `check_miss_px`: a few pixels is good, over about 10 means run it again. Run it again after any rotation change, because a calibration from another screen or rotation (including the portrait build's) is ignored. `--show` prints the stored map; `--show --clear` forgets it |
| 4 | Tap the face; press BOOT; hold BOOT. After row 6, tap the status strip (the no-app screen ignores it) | Wiggle; wiggle; listening face; face → threads → stats → face |
| 5 | Run `make run` in your terminal | Boop's eyes appear in the menu bar and the popover opens on setup: hello, a name and sweet or cheeky, which agents to watch ("See exactly what gets added" shows what goes where), then "Wake … up". Allow Bluetooth, Microphone and Speech Recognition when asked. Say whether setup and the popover feel right (A5) |
| 6 | Wait about 10 s | The app connects to `Boop-XXXX`, and the board leaves the no-app face. If Bluetooth won't connect, run `tools/boopctl bridge` and `app/.build/debug/Boop --link usb:/tmp/boop-bridge.sock` instead ([VERIFICATION.md](VERIFICATION.md) L4) |
| 7 | If you skipped them at setup: Settings (in the popover) → Agents → Connect for Claude Code and Codex. Restart open sessions, then run `skills/doctor/doctor.sh` in one, `echo BOOP_DOCTOR_PING`, and `skills/doctor/doctor.sh --confirm` | Both installed; the old `~/.boop` entries are gone; the doctor passes |
| 8 | In Claude Code, start a task | Working face within a second |
| 9 | Make Claude ask permission for a shell command | Amber and a look within about 1 s. Approve in the terminal → a nod, back to work |
| 10 | Let a task run past 5 minutes | A cheer, then maybe a mumble with a word |
| 11 | Make a turn fail | Oops, then a side-eye |
| 12 | In Codex, trigger an approval | Amber about 2 s after Codex asks. Requests its automatic reviewer handles don't light up |
| 13 | Hold BOOT and say "shut up for ten minutes" | Sulky face, quiet icon, no mumbles |
| 14 | Touch and hold the status strip, then trigger an approval | Focus icon; "needs you" is visual only |
| 15 | Later, open `~/Library/Application Support/Boop/short-term.md` | Today's notes and events |
| 16 | Listen to the voice clips on the Mac: `tools/.venv/bin/python tools/voicegen/voicegen.py --out /tmp/voice.h --wav-dir /tmp/boop-voice`, then `afplay /tmp/boop-voice/ba.wav` (and a few words, like `done.wav`) | Small, bright, chiptune syllables; the words are clear. Nobody has heard these yet |
| 17 | When an 8 Ω speaker is on the speaker header: `tools/boopctl voice --count 1` | Bouncy gibberish for each feeling, with the real word landing clearly; no pops when the amp switches |

Anything that's off becomes the next items in this plan (§7).

## 7. Open items

Known work that isn't a milestone yet. Drift found and not fixed goes here
too ([CLAUDE.md](../CLAUDE.md)). Pick one up by writing it into the
matching spec first.

- **Release.** Signing, notarisation, an app icon and a release pipeline
  don't exist for v1 yet. The gen-2 list is in
  [archived/docs/TODO-gen2.md](../archived/docs/TODO-gen2.md).
- **`zip` is drawn but nothing plays it.** [BEHAVIORS.md](BEHAVIORS.md)
  §3.3 has it on "shut up"; the rules don't send it, and the brain's `face`
  can't pick it.

From the J3 report's known issues (numbered as there):

- A3, brain tuning, deferred by the owner:
  - `note` on talk keeps praise and greetings, and sometimes misses a real
    fact ([#1](evidence/v1-build/REPORT.md#known-issues)).
  - The filler word `tests` is in most spoken lines, taps included
    ([#2](evidence/v1-build/REPORT.md#known-issues)).
  - A `moment` nearly every reflection, usually a retelling the action
    refuses; it pushes L5's drop rate over 5%
    ([#3](evidence/v1-build/REPORT.md#known-issues)).
  - Apple's guardrail refuses about 2 of 52 triggers; Boop keeps the rule
    reaction ([#4](evidence/v1-build/REPORT.md#known-issues)).
  - `remember("jetpack = payments")` is refused by memory's code check
    because of the `=` ([#5](evidence/v1-build/REPORT.md#known-issues)).
  - Sometimes two faces in one answer on events; one plays
    ([#6](evidence/v1-build/REPORT.md#known-issues)).
- The device and the link:
  - USB loses the odd line from the board to the Mac, for good: there are
    no sequence numbers ([#7](evidence/v1-build/REPORT.md#known-issues)).
  - Without the Mac, the board shows the no-app face after 30 s, so it
    can't be left on the idle face ([#8](evidence/v1-build/REPORT.md#known-issues)).
  - About 13 KB of heap headroom: 73 KB free against the 60 KB target
    ([#9](evidence/v1-build/REPORT.md#known-issues)).
  - A freshly built `boop-hook` takes about 250 ms on its first launch
    while macOS checks it ([#10](evidence/v1-build/REPORT.md#known-issues)).
  - The Codex fixtures are synthetic; no real Codex approval has been
    recorded ([#11](evidence/v1-build/REPORT.md#known-issues)).
  - The LED's green and amber were only checked in `dbg.state`, not seen
    ([#12](evidence/v1-build/REPORT.md#known-issues)).
  - SPI runs at 40 MHz; faster wasn't tried
    ([#14](evidence/v1-build/REPORT.md#known-issues)).
  - The owner's `~/.claude` and `~/.codex` still call the gen-2
    `~/.boop/boop-hook.sh` until the v1 setup replaces it
    ([#15](evidence/v1-build/REPORT.md#known-issues)).
