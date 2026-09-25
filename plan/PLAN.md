# Boop: plan

Updated 2026-09-25. The build order for v1, the check that closes each
milestone, how the unattended build runs, the owner's morning checklist,
and the later port to ESP-IDF + LVGL. The specs are listed in
[README.md](README.md); ideas that aren't in v1 are in
[FUTURE.md](FUTURE.md), so don't build them. [VERIFICATION.md](VERIFICATION.md)
defines the checks (L0–L6).

## 1. Starting point

**Code today** is the previous generation: `app/` (a Swift menu-bar app),
`firmware/esp32/` (firmware for a different board), their tools, and the
older generation in `archived/`. v1 **rewrites everything**, and no
existing code is off-limits. Delete anything v1 doesn't use, including
`archived/` code. The commit `gen2-final` keeps it all one command away.
Keep `landing/` (the live landing page) and the specs.

Reuse old code only where it fits the new architecture as is:

| Worth reusing | Where it goes |
| --- | --- |
| `HookInstaller.swift`: safe merging into `~/.claude/settings.json` and `~/.codex/hooks.json` | The installer |
| `BoopSignal/`: the compiled hook client (currently HTTP) | `boop-hook`, rewritten for the Unix socket |
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
- **Firmware tools:** PlatformIO is `/opt/homebrew/bin/pio`, and esptool is
  in `~/.platformio/penv/bin/`. There's 210 GB of disk free for toolchains.
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
                           Voice, Memory, DeviceLink, Talk
  Boop/                    the menu-bar app (also runs --headless)
  BoopHook/                boop-hook, the hook client
  HookWire/                what boop-hook and the app share: the hook line,
                           topic tags, the socket (Foundation only)
  BoopDev/                 boopdev: replay, talk, brain runs, memory dump
  Tests/                   unit tests, plus Fixtures/{hooks,triggers,memory}
firmware/                  PlatformIO project
  platformio.ini           envs: cyd24 (the board), native (Mac: tests + simulator)
  src/board/               pins, LovyanGFX config, button, touch, LED, DAC, battery
  src/render/              8-bit canvas, palette, fonts, face, screens (pure C++)
  src/app/                 protocol parser, behaviour state machine (pure C++)
  src/link/                USB serial and BLE transports, debug channel
  src/voice/               syllable player
  assets/                  generated fonts and voice samples (checked in)
  test/                    unit tests, scenarios/, golden/
tools/
  boopctl                  device tool (runs tools/.venv)
  voicegen/                builds the voice assets
  webcam/                  existing recorder
  build-loop.sh            runs the unattended build (§5)
Makefile                   build run test tools fw flash sim fw-test e2e
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
   before starting.
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
Sound (F5) comes late because there's no speaker to hear it.

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
| A3 | Harness and brains | Not started |
| A4 | Device link, app shell, push-to-talk, installer | Not started |
| J1 | End to end over USB | Not started |
| F5 | Voice on the device | Not started |
| J2 | Soak and polish | Not started |
| J3 | Handoff | Not started |
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
  amber), labelled corners, and a big UP arrow.
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
- **Face:** eye openness, pupil position, upper and lower lids, squash and
  stretch, and mouth curve and opening. Blends are eased and interruptible,
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
| 2 | Look at the board | The idle face, blinking |
| 3 | `tools/boopctl calibrate`, and tap the 4 targets | Touch lands where you tap |
| 4 | Tap the face; press BOOT; hold BOOT; tap the status strip | Wiggle; wiggle; listening face; face → threads → stats → face |
| 5 | Run `make run` in your terminal | The menu-bar icon appears. Allow Bluetooth, Microphone and Speech Recognition when asked |
| 6 | Wait about 10 s | The app connects to `Boop-XXXX`, and the board leaves the no-app face. If Bluetooth won't connect, run the app over USB instead ([VERIFICATION.md](VERIFICATION.md) L4) |
| 7 | Settings → install hooks for Claude Code and Codex; restart open sessions | Both installed; the old `~/.boop` entries are gone |
| 8 | In Claude Code, start a task | Working face within a second |
| 9 | Make Claude ask permission for a shell command | Amber and a look within about 1 s. Approve in the terminal → a nod, back to work |
| 10 | Let a task run past 5 minutes | A cheer, then maybe a mumble with a word |
| 11 | Make a turn fail | Oops, then a side-eye |
| 12 | In Codex, trigger an approval | Amber about 2 s after Codex asks. Requests its automatic reviewer handles don't light up |
| 13 | Hold BOOT and say "shut up for ten minutes" | Sulky face, quiet icon, no mumbles |
| 14 | Touch and hold the status strip, then trigger an approval | Focus icon; "needs you" is visual only |
| 15 | Later, open `~/Library/Application Support/Boop/short-term.md` | Today's notes and events |

Anything that's off becomes the next items in this plan.
