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
| `tools/` | `boopctl` (device tool), `voicegen` (voice assets), `fontgen` (the device's fonts), `webcam/` (opt-in recorder) |
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
make eval         # harness eval scenarios (app/Evals/scenarios) in chatty and calm, deterministic
make eval REAL=1  # the same with the real brains, 3 runs each, plus refusals and latency (L5)
make tools        # tools/.venv with pyserial and Pillow
make fw           # build firmware for the board
make flash        # build and upload over USB
make fw-test      # firmware unit tests on the Mac
make sim          # the renderer simulator
make e2e          # hook → app → USB → device pipeline check
make webcam-test  # the webcam recorder's tests, on synthetic video (no camera)
make run          # the Mac app, with Bluetooth; the owner runs this, not agents
tools/boopctl ping | state | shot | run <scenario> | sim <scenario> | bridge
tools/boopctl mumble [feeling] | say [feeling] | volume [level…] | sound [chirp] | moment [anim] [--say F] | needs
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
- `make build` re-signs `Boop` with the owner's self-signed "Boop Dev"
  certificate when it exists, so the Keychain doesn't ask for the Jev key
  after every rebuild ([plan/VERIFICATION.md](plan/VERIFICATION.md) §2).

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `tools/boopctl bridge` plus
  `Boop --headless --state-dir DIR --link usb:…`
  ([plan/VERIFICATION.md](plan/VERIFICATION.md) L4). Ask the owner to run
  `make run` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless it's authorised** (below).

## Architecture rules

The full picture is in [plan/ARCHITECTURE.md](plan/ARCHITECTURE.md). The
rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Actions (`react`, `quiet`, `remember`) carry out effects and check their
  own rules.
- **The harness is generic.** It runs the brain's two stages, checks their
  answers against the menu and hands each call to its action. It never
  builds Minion speech, writes files or talks to the device.
- **Only Voice knows Minion speech.** Only the memory store reads and writes
  the memory files. Only the device link knows Bluetooth or USB.
- **The brain is never on the event path.** Rules give the immediate
  reaction, and the brain adds character later or not at all.
- **The brain is assumed to be small** (by default plain rules decide and
  Apple's on-device model writes the words). Keep outputs few and flat,
  with mostly multiple-choice arguments, and keep deciding and writing
  apart.
- **`steering.md` is read-only at runtime.** `plan/steering.md` is the single
  source, and the app bundles a copy.
- **No code, file contents, prompts or agent transcripts go to the brain.**
  The only exception is the person's own words on push-to-talk.
- **"Needs you" and the screen priority are plain rules in the core.**
- **The device only renders and reports.** It receives the same messages
  over Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.

## Specs stay in sync

`plan/` is the contract, and the code must not drift from it. A change to
behaviour, a message, a budget, a flow, a command or a check updates the
matching spec in the same commit. Reviewers read the spec diff next to the
code diff.

**Start from the latest code.** In a worktree, check that
`git log --oneline HEAD..main` prints nothing before you compare or edit
anything. A worktree made from `origin/main` can be far behind a local
`main` that hasn't been pushed, and its specs describe different code.

**Which spec goes with which code** (specs are in `plan/`):

| When you change | Update |
| --- | --- |
| `app/BoopKit/Core/`, `firmware/src/app/behaviour.*` | `BEHAVIORS.md` |
| `app/Boop/`, `firmware/src/render/`, `firmware/src/app/gesture.*` | `UX.md` |
| `app/HookWire/`, `app/BoopHook/`, `app/BoopKit/Adapters/`, `app/BoopKit/Install/` | `ADAPTERS.md`, `ARCHITECTURE.md` §5 |
| `app/BoopKit/Harness/`, `app/BoopKit/Brains/`, `app/BoopKit/Core/Input.swift` | `HARNESS.md`, `steering.md` |
| `app/BoopKit/Actions/` | `ARCHITECTURE.md` §3, `HARNESS.md`, `steering.md` |
| `app/BoopKit/Memory/`, `app/BoopKit/App/` | `ARCHITECTURE.md` §3–4 |
| `app/BoopKit/Voice/`, `firmware/src/voice/`, `tools/voicegen/` | `VOICE.md` |
| `app/BoopKit/DeviceLink/`, `StateSnapshot.swift`, `firmware/src/link/`, `firmware/src/app/device.cpp`, `tools/boopctl_lib/` | `PROTOCOL.md` |
| `firmware/src/board/`, `firmware/platformio.ini` | `DEVICE.md` |
| `Makefile`, `tools/`, `app/BoopDev/`, `skills/`, tests | `VERIFICATION.md`, this file, `README.md` |
| `app/BoopKit/Eval/`, `app/Evals/` | `EVALS.md` |
| Structure, boundaries or a budget | `ARCHITECTURE.md` |
| What's in or out of v1 | `VISION.md` (Scope), `FUTURE.md` |
| A milestone's status | `PLAN.md` §4 |
| A spec added, renamed or removed | `plan/README.md`, this table |

**Rules that keep them from drifting:**

- **Say each fact once.** A number, name or rule lives in one spec; other
  docs link to it instead of restating it. When you change one, grep
  `plan/`, this file, `README.md`, `skills/`, `tools/*/README.md` and code
  comments for the old value or name, and fix every hit. Most drift so far
  is a copy left behind in a second doc.
- **Examples are real.** JSON, command lines and file layouts in a spec
  come from a test fixture or actual output, not from memory. When the
  shape changes, the example changes with it.
- **Commands run as written.** Every command in this file, `README.md`,
  `VERIFICATION.md` and the skills exists with those arguments. When you
  add, rename or remove a make target, a `boopctl` or `boopdev`
  subcommand, a flag or a path, grep the docs for it in the same commit.
- **Pin rules in tests.** When you implement or change a rule with a number
  in it (a timing, cap, threshold or priority), add or update a test that
  checks it and name the spec section in the test.
- **Removed code takes its docs with it.** Delete, or move to `archived/`,
  any doc, skill, checklist or code comment that describes code that's
  gone. A live doc for dead code is worse than none.
- **Status moves with the work.** When a milestone or task closes, update
  its row in `PLAN.md`, link its evidence from there, bump the "Updated"
  date on every spec you touched, and fix any summary that claims to be
  current, such as `plan/evidence/v1-build/REPORT.md`.
- **Drift you find but don't fix gets tracked.** Add it to `PLAN.md` as an
  open item. A note that lives only in evidence or a progress log gets
  lost.
- **Before you commit,** go through `git diff --stat` against the table
  above, check that `cmp CLAUDE.md AGENTS.md` is silent, and check that
  new or edited links resolve.

If a change deliberately departs from the spec, change the spec first and
add a row to the decision log in
[plan/ARCHITECTURE.md](plan/ARCHITECTURE.md) §11 saying why.

## Verification

Use the loop in [plan/VERIFICATION.md](plan/VERIFICATION.md): unit tests,
then the simulator (look at the PNGs), then the device over USB (pixel
identical to the simulator), then the webcam when authorised. Report only
checks that actually ran and passed. A milestone's evidence goes in
`plan/evidence/v1-build/<milestone>/` ([plan/VERIFICATION.md](plan/VERIFICATION.md)
§7); other work goes in `plan/evidence/<date>-<topic>/`. Link either from
`PLAN.md`. Raw webcam footage never goes into git.

## Webcam

Webcam verification is opt-in. Use the `webcam-verify` skill
(`skills/webcam-verify/SKILL.md`) only when the owner asks for it and
confirms the physical setup for that session. The v1 build was
authorised to use it until the owner withdrew that on 2026-09-26
(`plan/evidence/v1-build/PROGRESS.md`). Clips are bounded, video only, and raw
footage stays local.

## Self-diagnosis

The `doctor` skill (`skills/doctor/doctor.sh`) checks hook registration, the
running app's socket, a synthetic round trip and, with `--confirm`, that
this agent's own hooks fire. `--headless` checks against a throwaway
headless app instead. Don't launch the Boop app yourself; ask the owner.

## Documentation

- `README.md` stays an overview with build, run and test commands.
- History and earlier research live in `archived/`. Don't extend them.
