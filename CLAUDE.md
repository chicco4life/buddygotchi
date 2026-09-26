# Boop Agent Instructions

These instructions apply to the whole repo. Keep this file mirrored in
`CLAUDE.md` and `AGENTS.md`.

## What Boop is

Boop is a small desk creature with a personality of its own that watches
your Claude Code and Codex agents. It mumbles in Minion-like gibberish,
tells you when an agent needs your approval on the Mac, and cheers when
work finishes. It never approves anything. A Mac app does the thinking; a
cheap ESP32 board with a screen is the body. Start with
[plan/VISION.md](plan/VISION.md).

## Repo layout

| Path | What it is |
| --- | --- |
| `plan/` | The spec. It's the contract the code implements. [plan/PLAN.md](plan/PLAN.md) has the build order and status, and [plan/VERIFICATION.md](plan/VERIFICATION.md) has how everything is checked. Evidence goes in `plan/evidence/` |
| `app/` | Swift package: the Mac menu-bar app, the `boop-hook` hook client, and the `boopdev` dev CLI |
| `firmware/` | PlatformIO firmware for the MicroTech MTR024QV01A board ([plan/DEVICE.md](plan/DEVICE.md)) |
| `tools/` | `boopctl` (device tool), `voicegen` (voice assets), `webcam/` (opt-in recorder) |
| `skills/` | `doctor` (hook self-check) and `webcam-verify`, symlinked for Claude, Codex and Cursor |
| `archived/` | History only: research, docs and the gen-2 specs (`archived/plan-gen2`). All earlier code is kept at git tag `gen2-final` (`git show gen2-final:<path>`). Don't extend it |
| `landing/` | The Next.js landing page (Vercel project root) |

v1 is a rewrite, and no existing code is off-limits: delete anything v1
doesn't use, including `archived/` code (the tag `gen2-final` keeps it).
Keep `landing/` and the specs.

## Build and test

Run from the repo root.

```sh
make build        # Mac app, boop-hook, boopdev
make test         # Swift unit tests (XCTest shim; there is no Xcode here)
make tools        # tools/.venv with pyserial and Pillow
make fw           # build firmware for the board
make flash        # build and upload over USB
make fw-test      # firmware unit tests on the Mac
make sim          # the renderer simulator
make e2e          # hook → app → USB → device pipeline check
make run          # the Mac app, with Bluetooth; the owner runs this, not agents
tools/boopctl ping | state | shot | run <scenario> | sim <scenario> | bridge
app/.build/debug/Boop --snapshots DIR   # the Mac app's popover and icons as PNGs, no Bluetooth
```

**Environment notes:**

- There's no Xcode, so `swift test` runs nothing. `make test` runs
  `python3 app/tools/test.py`, which generates the shim runner and runs
  `swift run BoopTests`.
- Command Line Tools lack some Swift macro plugins. SwiftUI's `@State` and
  Foundation Models' `@Generable`/`@Guide` don't compile. Use the
  `ViewState` alias and runtime `DynamicGenerationSchema` instead
  ([plan/PLAN.md](plan/PLAN.md) §1).
- If a SwiftPM build fails before compiling, with module-cache errors under
  `~/.cache/clang` or `~/Library/org.swift.swiftpm`, rerun it outside the
  sandbox before investigating the source.
- Apple's Foundation Models runs from the shell (8K context).
- PlatformIO is `/opt/homebrew/bin/pio`. Call it through
  `firmware/tools/pio.sh` (the make targets do), which keeps its packages in
  `firmware/.platformio-core`. The board shows up as
  `/dev/cu.usbserial-*`. The serial port needs no special permissions.
- System Python has no pyserial or Pillow. The tools use `tools/.venv`.

## Running the v1 build

"Run the loop" or "start the build" means: from this checkout's root, start
`caffeinate -dimsu tools/build-loop.sh` as a background command and report
where its log is (`/tmp/boop-build-loop/loop.log`). The script runs
[plan/LOOP.md](plan/LOOP.md) one fresh iteration at a time until
`plan/evidence/v1-build/DONE` exists ([plan/PLAN.md](plan/PLAN.md) §5).
Don't run the iterations yourself in this session.

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `tools/boopctl bridge` plus
  `Boop --headless --link usb:…` ([plan/VERIFICATION.md](plan/VERIFICATION.md)
  L4). Ask the owner to run `make run` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless it's authorised** (below).

## Architecture rules

The full picture is in [plan/ARCHITECTURE.md](plan/ARCHITECTURE.md). The
rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Actions (`say`, `face`, `quiet`, `note`, …) carry out effects and check
  their own rules.
- **The harness is generic.** It builds the prompt, calls the model, checks
  the answer's shape and routes tool calls. It never builds Minion speech,
  writes files or talks to the device.
- **Only Voice knows Minion speech.** Only the memory store reads and writes
  the memory files. Only the device link knows Bluetooth or USB.
- **The brain is never on the event path.** Rules give the immediate
  reaction, and the brain adds character later or not at all.
- **The brain is assumed to be small** (Apple's on-device model by default).
  Keep tools few and flat, with mostly multiple-choice arguments.
- **`steering.md` is read-only at runtime.** `plan/steering.md` is the single
  source, and the app bundles a copy.
- **No code, file contents, prompts or transcripts go to the brain.** The
  only exception is the person's own words on push-to-talk.
- **XP, hunger, mood, "needs you" and the screen priority are plain rules in
  the core.**
- **The device only renders and reports.** It receives the same messages
  over Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.

## Specs stay in sync

`plan/` is the contract, and the code must not drift from it. A change to
behaviour, a message, a budget, a flow or a check updates the matching spec
in the same commit:

| Area | Spec |
| --- | --- |
| What the person sees | `UX.md`, `BEHAVIORS.md` |
| Messages between the Mac and the device | `PROTOCOL.md` |
| Structure, boundaries, memory files, budgets | `ARCHITECTURE.md` |
| Hooks and "needs you" | `ADAPTERS.md` |
| The brain | `HARNESS.md`, `steering.md` |
| The gibberish | `VOICE.md` |
| Hardware and firmware stack | `DEVICE.md` |
| How it's checked | `VERIFICATION.md` |
| Build order and status | `PLAN.md` |

If a change deliberately departs from the spec, change the spec first and
add a row to the decision log in
[plan/ARCHITECTURE.md](plan/ARCHITECTURE.md) §11 saying why.

## Verification

Use the loop in [plan/VERIFICATION.md](plan/VERIFICATION.md): unit tests,
then the simulator (look at the PNGs), then the device over USB (pixel
identical to the simulator), then the webcam when authorised. Report only
checks that actually ran and passed. Write evidence to
`plan/evidence/<date>-<topic>/`. Raw webcam footage never goes into git.

## Webcam

Webcam verification is opt-in. Use the `webcam-verify` skill
(`skills/webcam-verify/SKILL.md`) only when the owner asks for it and
confirms the physical setup for that session. The build loop prompt
([plan/LOOP.md](plan/LOOP.md)) authorises it for the v1 build run only.
Clips are bounded, video only, and raw footage stays local.

## Self-diagnosis

The `doctor` skill (`skills/doctor/doctor.sh`) checks hook registration, the
running app's socket, a synthetic round trip and, with `--confirm`, that
this agent's own hooks fire. `--headless` checks against a throwaway
headless app instead. Don't launch the Boop app yourself; ask the owner.

## Documentation

- `README.md` stays an overview with build, run and test commands.
- History and earlier research live in `archived/`. Don't extend them.
