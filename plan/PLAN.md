# Boop: plan

Draft 1 · 2026-09-25. The build order for v1, the check that closes each
milestone, the rules for the overnight run, the owner's morning checklist,
and the later port to ESP-IDF + LVGL. The specs in this folder are the
contract; [VERIFICATION.md](VERIFICATION.md) defines the checks (L0–L6).

## 1. Starting point

**Specs:** [VISION](VISION.md) · [UX](UX.md) · [ARCHITECTURE](ARCHITECTURE.md)
(decisions in §11) · [ADAPTERS](ADAPTERS.md) · [HARNESS](HARNESS.md) ·
[steering.md](steering.md) · [PROTOCOL](PROTOCOL.md) ·
[BEHAVIORS](BEHAVIORS.md) · [VOICE](VOICE.md) · [DEVICE](DEVICE.md) ·
[VERIFICATION](VERIFICATION.md).

**Code today** is the previous generation: `app/` (a Swift menu-bar app) and
`firmware/esp32/` (firmware for a different board). v1 **rewrites
everything**. Tag the starting commit `gen2-final`, so the old code stays
one command away. Salvage something only when it fits the new architecture
as is:

| Worth salvaging | Where it goes |
| --- | --- |
| `HookInstaller.swift`: safe merging into `~/.claude/settings.json` and `~/.codex/hooks.json` | Adapters: the installer |
| `BoopSignal/`: the compiled hook client (currently HTTP) | `boop-hook`, rewritten for the Unix socket |
| `BLEManager.swift`: the CoreBluetooth Nordic UART central | Device link: Bluetooth transport |
| `VoiceRuntime.swift`: Foundation Models session setup | Brains: Apple |
| `app/Tests/Fixtures/hooks/`: recorded real hook payloads | Adapter tests and end-to-end fixtures |
| `app/TestSupport/XCTestShim` and `app/tools/gen-test-runner.py` | Kept as is: tests without Xcode |
| `InstanceLock.swift`, headless and isolated-instance ideas | App shell: `--headless` mode |
| `buddyctl.py`: serial locking, framing, PNG writer | `tools/boopctl` |
| `tools/webcam/` | Kept as is |

Everything else goes: SQLite, the HTTP server, the old reducer and engine,
turn moments, the Waveshare firmware and its tools.

**Environment facts** (checked 2026-09-25):

- **Mac:** macOS 27 with Command Line Tools only, no Xcode. Swift tests run
  through the shim, via `make test`.
- **Apple's model:** Foundation Models is available from the shell, with an
  8K context.
- **Firmware tools:** PlatformIO is at `/opt/homebrew/bin/pio`, and esptool
  is in `~/.platformio/penv/bin/`.
- **Board:** on `/dev/cu.usbserial-110` (the number can change). It's an
  ESP32-D0WD-V3 with 4 MB flash, auto-reset works, and the factory demo is
  on it.
- **Camera:** "MacBook Air Camera", id `6C707041-05AC-0010-000D-000000000001`.
- **Python:** system `python3` is 3.14 without pyserial or Pillow. `make
  tools` creates `tools/.venv` with both (tested).
- **Bluetooth:** an agent can't launch the app with Bluetooth on, or run
  `bleak`. macOS's privacy system kills it. USB serial works fine.

## 2. Target layout

```
app/                       Swift package
  BoopKit/                 library: Adapters, Core, Harness, Brains, Actions,
                           Voice, Memory, DeviceLink, Talk
  Boop/                    the menu-bar app (also runs --headless)
  BoopHook/                boop-hook, the hook client
  BoopDev/                 boopdev: replay, brain runs, memory dump
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
Makefile                   build run test tools fw flash sim fw-test e2e
```

`plan/steering.md` is the single source for steering. The build copies it
into the app's resources, and a unit test fails if the copies differ.

## 3. Rules for the overnight run

1. **Branch and commits.** Work on branch `v1-overnight`. Tag the starting
   commit `gen2-final`. Commit after each milestone passes its check, never
   with failing tests. Message: `M3: device behaviour — <one line>`.
2. **Specs are the contract.** If the implementation has to differ, change
   the spec in the same commit and add a line to
   [ARCHITECTURE.md](ARCHITECTURE.md) §11.
3. **Don't touch the owner's setup.** Never modify `~/.claude`, `~/.codex`
   or the everyday app's state. Tests use a temporary `HOME` and isolated
   state directories.
4. **No Bluetooth from the agent.** Don't launch the app with Bluetooth and
   don't run `bleak`. Anything live goes over USB, through `boopctl bridge`.
5. **Webcam:** authorised for this run only, under
   [VERIFICATION.md](VERIFICATION.md) §6. The owner positions the board
   before starting.
6. **Stay awake.** The run is started under `caffeinate -dimsu`, with the
   lid open.
7. **Don't get stuck.** If one problem takes about 45 minutes, write it up in
   the report (what failed, what was tried, the best guess) and move to the
   next milestone that doesn't depend on it. The firmware track (F) and the
   app track (A) are independent until J1. With two agents, run one per
   track.
8. **Leave the board clean.** At the end, flash the final normal firmware and
   leave it on the idle face, or on the test pattern if bring-up failed.
9. **Keep the checks honest.** Only report a check as passed if it ran and
   passed. If a check was skipped or changed, say so and why.

## 4. Milestones

The order for one agent: **M0 → F1 → F2 → F3 → A1 → A2 → A3 → A4 → J1 → F4 →
F5 → J2 → J3.** Bluetooth (F4) and sound (F5) come late because they can't be
fully checked tonight anyway.

| # | Milestone | Status |
| --- | --- | --- |
| M0 | Setup | Not started |
| F1 | Board bring-up | Not started |
| F2 | Renderer and simulator | Not started |
| F3 | Device behaviour | Not started |
| F4 | Bluetooth on the device | Not started |
| F5 | Voice on the device | Not started |
| A1 | App core: adapters, hook client, core rules | Not started |
| A2 | Memory, Voice, actions | Not started |
| A3 | Harness and brains | Not started |
| A4 | Device link, app shell, push-to-talk, installer | Not started |
| J1 | End to end over USB | Not started |
| J2 | Soak and polish | Not started |
| J3 | Handoff | Not started |
| P1 | Port to ESP-IDF + LVGL (later, gated) | Not started |

### M0: Setup

- Tag `gen2-final`, then create branch `v1-overnight`.
- Remove `firmware/esp32/`. Create the new PlatformIO project in
  `firmware/` with envs `cyd24` and `native`. A wrapper keeps PlatformIO's
  packages inside the worktree, as `pio_ws.sh` did.
- Restructure `app/` into the target layout. Remove the old sources and the
  `wire`/Hummingbird dependencies. Keep the XCTest shim working.
- Create `tools/boopctl` and `make tools` (venv with pyserial and Pillow).
- Update the Makefile targets: `build run test tools fw flash sim fw-test e2e`.
- Update the commands in CLAUDE.md and AGENTS.md if they differ from what
  was built.

**Done when:** `make build`, `make test` (at least one test), `make fw`,
`make fw-test` and `make tools` all succeed, and `tools/boopctl ports` lists
the board.

### F1: Board bring-up

- LovyanGFX config ([DEVICE.md](DEVICE.md) §4): screen on SPI2, touch on
  SPI3, PWM backlight.
- The 8-bit canvas, allocated first, and pushing only the changed rows.
- The test pattern: 6 large colour blocks (red, green, blue, white, black,
  amber), labelled corners, and a big UP arrow.
- USB link at 921600 baud with `dbg.ping`, `dbg.state`, `dbg.shot`,
  `dbg.clock`, `dbg.pattern`, `dbg.press` and `dbg.touch`.
- BOOT gestures: shorter than 400 ms is a tap; 400 ms or more is
  push-to-talk until release.
- RGB LED with PWM, amp off by default, battery ADC, raw touch readings.
- The `native` env builds the canvas and pattern, so the simulator can
  render the pattern already.

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
  in amber with squiggles.
- **Simulator:** `boop-sim` runs a scenario and writes PNGs through
  `boopctl sim`.
- **Goldens:** one for every screen and state in [UX.md](UX.md) and
  [BEHAVIORS.md](BEHAVIORS.md).

**Done when:**

- L0: canvas and face-parameter tests pass.
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
  at 2 min. On this board the buzz is three amber light pulses. Focus mode
  makes it visual only.
- **Quiet:** respects `quiet`.
- **Moments:** the animation set with sizes and time-to-live, with a new
  moment replacing a playing one.
- **Mouth:** syncs to `say`, even without audio.
- **Inputs:** tap, hold and strip gestures from [UX.md](UX.md) §4, with local
  feedback within 20 ms and an `input` message sent to the Mac.
- **Other screens:** screen cycling, threads and stats, the no-app screen
  after 30 s of silence, night dimming, hunger (tummy rumble), and status
  strip icons.

**Done when:**

- L0: state-machine tests pass, including every timing.
- L1: every row in [BEHAVIORS.md](BEHAVIORS.md) §3 has a reviewed golden.
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

### F5: Voice on the device

- **Voice assets:** `tools/voicegen` synthesises about 60 syllables and about
  40 words ([VOICE.md](VOICE.md)): macOS `say` → `afconvert` → pitch up and
  normalise → 8-bit samples at 11.025 kHz → `firmware/assets/voice.h`.
- **Player:** enables the amp, runs the continuous DAC at 22.05 kHz, and
  resamples in software for pitch and tempo. It follows volume, focus,
  quiet and mute.

**Done when:**

- L0: resampler tests pass.
- L2: the audio timeline in `dbg.state` matches `say` (syllable count, and
  duration within 10%).
- The firmware fits its app slot with at least 15% to spare, and heap stays
  within budget.
- Hearing it waits for a speaker.

### A1: App core

- **Adapters:** Claude and Codex mappings ([ADAPTERS.md](ADAPTERS.md) §3),
  with project names from `cwd` (worktrees map to their repo).
- **Hook client:** `boop-hook` on the Unix socket. 50 ms connect timeout,
  256 KB input cap, never prints, always exits 0. The app side is the socket
  server.
- **Core:** the session table and the "needs you" rules (start, clear, the
  2 s Codex grace period, the 10-minute safety net). Screen priority, the
  `state` snapshot builder, XP, hunger and levels ([BEHAVIORS.md](BEHAVIORS.md)
  §4), mood rules, and quiet, focus and away. Triggers go to the harness
  with 3 s coalescing and the core's gates.

**Done when:**

- L0: mapping tests pass on the recorded fixtures.
- `boop-hook` exits in under 50 ms when the app isn't running.
- Core rule tests pass for every row of [BEHAVIORS.md](BEHAVIORS.md) §3.1–3.2
  and §4.
- `boopdev replay` on a fixture prints the expected `state` snapshots.

### A2: Memory, Voice and actions

- **Memory store:** the three files and their formats
  ([ARCHITECTURE.md](ARCHITECTURE.md) §4), with limits, atomic writes, and
  snapshots to `history/`. A file that won't parse is restored from the last
  snapshot. The first activity of a new day runs `reflect`, then starts
  short-term fresh.
- **Voice:** the syllable set, dialect from the seed, feelings, tune, and
  tempo from mood ([VOICE.md](VOICE.md) §3–6). The English check uses
  `/usr/share/dict/words` for strings of 3+ letters, plus a list of rude and
  sensitive words and a list of Minion words. Up to 5 retries, then the safe
  hum.
- **Actions:** `say`, `face`, `quiet`, `note`, `remember`, `forget`,
  `temperament` and `moment`. Each owns its tool definition and its own
  checks. `say` → Voice → device link.

**Done when:**

- L0: every memory limit is enforced, snapshots and restore work, and Voice
  is deterministic. A property test of 10,000 generated lines finds zero
  dictionary hits.
- Every action drops invalid input, and says why in the log.

### A3: Harness and brains

- **Harness** ([HARNESS.md](HARNESS.md) §3): the tool registry, one call at
  a time with replace and cancel, the prompt builder with budgets, the shape
  check, dispatch, and the debug log.
- **Brains:**
  - **Apple:** guided generation into a response of up to 3 calls, with
    enums constrained.
  - **Rules only:** reads the fallback table in `steering.md`.
  - **Cloud:** interface only, left disabled.

**Done when:**

- L0: harness tests with a fake brain pass (shape rejection, cancel, replace,
  at most 3 calls).
- L5: the brain run on at least 50 fixture triggers passes, and its sample
  is reviewed.

### A4: Device link, app shell, push-to-talk and installer

- **Device link:**
  - **Bluetooth central:** scans for `Boop-*`, connects, sends `state` on
    change and every 10 s, receives `input` and `status`, and reconnects.
  - **USB transport:** through the bridge socket.
- **App shell:**
  - **Menu bar:** the icon (dot or amber) and the popover ([UX.md](UX.md)
    §7).
  - **Settings:** name, brain choice, API key (stored in the Keychain; the
    cloud brain is shown as not yet available), hooks install and remove, and
    device status.
  - **Headless mode:** `--headless --state-dir --link --socket`.
- **Push-to-talk:** `talk_on` starts the Mac mic, with on-device speech
  recognition from the Speech framework. `talk_off` ends it and sends a
  `talk` trigger. Info.plist carries the usage descriptions.
- **Installer:** install, repair and remove Boop's entries in
  `~/.claude/settings.json` and `~/.codex/hooks.json`, leaving other entries
  alone.
- **Doctor:** update `skills/doctor/doctor.sh` for the socket.

**Done when:**

- L0: installer tests pass on a temporary `HOME`. They're idempotent, keep
  other hooks, and remove only Boop's entries.
- Device-link encoding tests pass.
- The app builds, and headless mode starts and stops cleanly.

### J1: End to end over USB

- Fixtures:
  - a Claude session with a prompt, tools, `PermissionRequest`, activity, a
    long `Stop`, and a `StopFailure`;
  - Codex requests, one resolved within 2 s (no "needs you") and one
    resolved after 10 s ("needs you" appears at 2 s).
- Run the headless app, the bridge and replay ([VERIFICATION.md](VERIFICATION.md)
  L4).

**Done when:**

- L4 passes: every checkpoint matches, with p95 latency under 200 ms.
- The memory files and XP change as specified.
- The brain's moments arrive after the rule reactions.
- L3: a webcam clip of a full Claude session is reviewed.

### J2: Soak and polish

**Done when:**

- A 30-minute soak with replayed traffic and the Apple brain on shows no
  resets, no leaks and no stuck states.
- All tests are green and all goldens reviewed.
- `README.md` describes the new product and commands.

### J3: Handoff

- Write `plan/evidence/<date>-overnight/REPORT.md`. It covers each
  milestone (passed, blocked or skipped, with evidence links), known
  issues, anything the morning checklist should do differently, and the
  confirmed panel settings.
- Flash the final firmware, leave it on the idle face, and commit.
- Update the status table above.

### P1: Port to ESP-IDF + LVGL (later)

**Gate:** only after the owner has run the morning checklist and confirmed
v1 works. Then port *everything*, including the tools and the checks:

- **Project:** ESP-IDF, via PlatformIO `framework = espidf` or `idf.py`,
  with the `esp_lcd` ST7789 driver and `esp_lcd_touch_xpt2046`, on separate
  SPI hosts as today.
- **Drawing:** LVGL 9 through `esp_lvgl_port`. Boop's canvas renderer stays
  and is presented through an LVGL canvas. Screens that benefit from
  widgets (threads, stats) can move to LVGL.
- **Everything else:** raw NimBLE Nordic UART, the continuous DAC, NVS, and
  the same USB debug channel with `dbg.shot` (from the canvas, or
  `lv_snapshot_take`).
- **Tools:** `boopctl`, the scenarios, the goldens and the webcam checks stay
  the same, because the protocol doesn't change. If screens move to LVGL,
  the simulator adds LVGL's desktop build.

**Done when:**

- The whole L0–L4 suite passes against the ESP-IDF build without changes.
- Screenshots match the Arduino goldens, or the differences are reviewed.
- Performance is the same or better, and the RAM and flash budgets are
  updated in [DEVICE.md](DEVICE.md).

After P1: Secure Boot v2, flash encryption, and Bluetooth bonding, as their
own milestone.

## 5. Before you sleep (owner)

1. Plug the Mac into power. Leave the board on USB.
2. Position the board facing the MacBook camera: the whole screen visible,
   about 30–40 cm away, even light, no glare.
3. Grant camera access once, and check the framing:
   `tools/webcam/webcam.sh record --camera 6C707041-05AC-0010-000D-000000000001 --seconds 3 --out /tmp/boop-framing`.
   Accept the camera prompt if it appears.
4. Start the run from the repo root: `caffeinate -dimsu claude`. Paste the
   kickoff prompt (§7), and leave the lid open.

## 6. Morning checklist (owner)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Read `plan/evidence/<date>-overnight/REPORT.md` | What passed, what's blocked, and any changes to these steps |
| 2 | Look at the board | The idle face, blinking |
| 3 | `tools/boopctl calibrate`, and tap the 4 targets | Touch lands where you tap |
| 4 | Tap the face; press BOOT; hold BOOT; tap the status strip | Wiggle; wiggle; listening face; face → threads → stats → face |
| 5 | Run `make run` in your terminal | The menu-bar icon appears. Allow Bluetooth, Microphone and Speech Recognition when asked |
| 6 | Wait about 10 s | The app connects to `Boop-XXXX`, and the board leaves the no-app face |
| 7 | Settings → install hooks for Claude Code and Codex; restart open sessions | Both show as installed |
| 8 | In Claude Code, start a task | Working face within a second |
| 9 | Make Claude ask permission for a shell command | Amber and a look within about 1 s. Approve in the terminal → a nod, back to work |
| 10 | Let a task run past 5 minutes | A big cheer, then maybe a mumble with a word |
| 11 | Make a turn fail | Oops, then a side-eye |
| 12 | In Codex, trigger an approval | Amber about 2 s after Codex asks. Requests its automatic reviewer handles don't light up |
| 13 | Hold BOOT and say "shut up for ten minutes" | Sulky face, quiet icon, no mumbles |
| 14 | Touch and hold the status strip, then trigger an approval | Focus icon. "Needs you" is visual only |
| 15 | Later, open `~/Library/Application Support/Boop/short-term.md` | Today's notes and events |

Anything that's off becomes the next items in this plan.

## 7. Kickoff prompt

Paste this into a fresh Claude Code session started with
`caffeinate -dimsu claude` from the repo root:

```
Implement Boop v1 overnight by following plan/PLAN.md.

Read CLAUDE.md, then plan/PLAN.md, plan/VERIFICATION.md, plan/ARCHITECTURE.md
and plan/DEVICE.md, then the other specs as each milestone needs them.
Work through the milestones in the order PLAN.md §4 gives, obeying the rules
in §3. For each milestone: build it, run every check listed under "Done
when" using the loop in VERIFICATION.md, write the milestone's evidence
notes, commit, update the status table, and move on. Do not stop to ask me
anything; I'm asleep. If something blocks you for about 45 minutes, record
it and continue with the next independent milestone.

Webcam verification is authorised for this run only (VERIFICATION.md §6).
The board is already positioned facing the MacBook Air camera; start with
the framing check.

Finish with J3: the report, the final firmware flashed on the idle face,
and everything committed on branch v1-overnight. Then push the branch to
origin.
```

Delete the last sentence of the prompt if the branch shouldn't be pushed.
