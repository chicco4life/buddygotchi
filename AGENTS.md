# Boop Agent Instructions

These instructions apply to the whole repo. `CLAUDE.md` and `AGENTS.md`
are the same file: edit `CLAUDE.md`, then copy it over `AGENTS.md`.

## What Boop is

Boop is a small desk creature with a personality of its own that watches
your Claude Code and Codex agents. It grunts, huffs and says the odd word,
tells you when an agent needs your approval on the Mac, and celebrates
work that earns it. It never approves anything. A Mac app does the thinking; a
cheap ESP32 board with a screen is the body. Start with
[documentation/VISION.md](documentation/VISION.md).

## Repo layout

| Path | What it is |
| --- | --- |
| `documentation/` | The spec, which the code implements ([the index](documentation/README.md)). [documentation/MODULES.md](documentation/MODULES.md) says how the three packages below join Boop, and [documentation/VERIFICATION.md](documentation/VERIFICATION.md) how everything is checked. Evidence goes in `documentation/evidence/` |
| `Package.swift` | The Swift package, at the root because its targets are in both `app/` and `internal/`. It builds into `.build/` |
| `agent-hooks/` | The hook layer, a Swift package of its own meant to be open-sourced ([its README](agent-hooks/README.md), [its spec](agent-hooks/SPEC.md)): the `agent-hook` hook client, the `agent-hooks` command line, and the `AgentHooks` library that turns hooks into events and keeps the sessions and "needs you". It depends on nothing else in the repo; Boop depends on it |
| `jharness/` | The brain's harness, a Swift package of its own meant to be open-sourced ([its README](jharness/README.md), [its spec](jharness/SPEC.md)): the `JHarness` library (events and the log, each kind's line, rules, outputs and `Choice`, the prompt, Jev and the loop that asks it), `jharness-emit`, and its worked example Beacon (`beacon`). It depends on nothing else in the repo; Boop's brain runs on it |
| `linkkit/` | The device link, a package of its own meant to be open-sourced ([its README](linkkit/README.md), [its spec](linkkit/SPEC.md)): the protocol (four JSON messages, and the turn, by which the device decides what plays when), the Swift host library `LinkKit` with its Bluetooth and socket transports, `linkkit-bridge` (the USB bridge), and the C++ device library in `linkkit/device/` ([its README](linkkit/device/README.md)), with its own PlatformIO project for its tests, that Boop's firmware plugs into. It depends on nothing else in the repo; Boop depends on it |
| `app/` | The Mac side that ships: the menu-bar app (`Boop`) and the `BoopKit` library, Boop's own code on the three packages |
| `firmware/` | PlatformIO firmware for the MicroTech MTR024QV01A board ([documentation/DEVICE.md](documentation/DEVICE.md)): Boop's app on LinkKit's device library, with its generated assets and build scripts |
| `internal/` | Everything that doesn't ship ([its README](internal/README.md)): `boopdev` and its library, Boop's Swift tests and eval scenarios, the sources of `Boop --headless` and `--snapshots`, and the firmware's simulator and unit tests (env `native`) |
| `internal/tools/` | `boopctl` (device tool, and `boopctl workday`, a scripted working day through the brain), `voicegen` (voice assets), `sfxgen` (the sound effects, from the animation bank), `fontgen` (the device's fonts), `facegen` (the device's faces, from the animation bank), `webcam/` (opt-in recorder) |
| `internal/skills/` | `doctor` (hook self-check) and `webcam-verify`, symlinked for Claude, Codex and Cursor |
| `landing/` | The Next.js landing page (Vercel project root) |
| `internal/boop-design/` | The animation bank, the code the device's designs and sounds are built from (facegen and sfxgen run it), with its offline review, and the mood-graph handover ([guide](internal/boop-design/README.md)) |

Code that doesn't ship goes in `internal/`: tests, evals, dev tools,
skills and the simulator. What ships (`BoopKit`, `Boop`, the three
packages agent-hooks, jharness and linkkit, LinkKit's device library and
the firmware) never depends on internal code, and `make build` fails if a
Swift target imports one it doesn't declare. The packages depend on
nothing of Boop's and nothing outside their folders; the device library's build fails if it
includes a header that isn't its own (`linkkit/device/tools/check_includes.py`).
Their own tests live in each package. The one overlap is `Boop --headless` and
`Boop --snapshots`, flags of the shipped app whose sources are in
`internal/app/Boop/`.

Delete code that nothing uses; git keeps it. The old research, docs,
gen-2 specs and the finished v1 build plan with its full decision log
lived in `archived/`, now at git tag `archived-final`
(`git show archived-final:archived/<path>`); gen-2 code is at tag
`gen2-final`.

## Commands

The everyday entry points are in [README.md](README.md), which stays a
short overview. The root `Makefile` has only what the owner uses: `build`,
`app`, `run`, `debug`, `dash`, `day`, `flash`, `eval` and `clean`. The development targets
(`test`, `tools-test`, `voice`, `fw`, `fw-test`, `sim`, `e2e`, `faces`, `tools`)
are in `internal/Makefile`; run them from the repo root as
`make -C internal <target>`. Every make target and tool is in
[documentation/VERIFICATION.md](documentation/VERIFICATION.md) §2, and each CLI prints its
flags with `--help`. `make run` and `make debug` use Bluetooth, so they're
the owner's. For agents:

```sh
make build                                            # Mac app, boopdev, the tests' runner, agent-hook, jharness-emit, beacon and linkkit-bridge (make -C internal test and make eval build too)
make -C internal test                                 # Swift unit tests: Boop's, then swift test in agent-hooks/, jharness/ and linkkit/
.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth, printing everything
.build/debug/Boop --snapshots DIR                     # the popover's panes and the menu-bar icons as PNGs, then exits
```

## Environment notes

- There's no Xcode, so XCTest is missing and `swift test` runs nothing of
  Boop's. `make -C internal test` runs `make build`, which generates the
  XCTest shim's runner and builds the package in one `swift build`, then
  runs `.build/debug/BoopTests`. Then it runs the three packages' own
  tests, which use Swift Testing, as
  `swift test --scratch-path .build/tests` in `agent-hooks/`,
  `jharness/` and `linkkit/` in turn.
  That build now and then fails with "plugin for module 'TestingMacros'
  not found", a toolchain flake, even from a clean build folder; it
  passes when run again, so the target tries that failure alone again, up
  to seven times (eight tries in all). LinkKit's device library has no
  Swift: its own tests (`linkkit/device/test/`) run after the firmware's
  in `make -C internal fw-test`.
- Command Line Tools lack some Swift macro plugins, so SwiftUI's `@State`
  doesn't compile. Write `@ViewState` (the alias in
  `app/Boop/Views/ViewState.swift`).
- If a SwiftPM build fails before compiling, with module-cache errors under
  `~/.cache/clang` or `~/Library/org.swift.swiftpm`, rerun it outside the
  sandbox before investigating the source.
- `boopdev` and `Boop --headless` read Jev's API key only from
  `BOOP_JEV_KEY`, so Jev runs (`make eval`) need the owner to supply it.
  `Boop --headless --brain scripted` runs the whole pipeline without it. Never read the
  Keychain from an agent shell, and don't go looking for the key.
- PlatformIO is `/opt/homebrew/bin/pio`. Call it through
  `firmware/tools/pio.sh` (the make targets do), which keeps its packages
  in `firmware/.platformio-core`. The board shows up as
  `/dev/cu.usbserial-*` (the AMOLED board, env `amoled206`, as
  `/dev/cu.usbmodem*`; documentation/DEVICE.md §9), and the serial port needs no
  special permissions.
- System Python has no pyserial, Pillow or Textual. The tools use
  `internal/tools/.venv`, which `internal/tools/boopctl` makes on its
  first run (`make -C internal tools` refreshes it).
- A Unix socket's path has room for 103 bytes, so give `Boop --headless`
  a short state directory (under `/tmp`) or a short `--socket`.
- Webcam recording works only from a terminal the Claude app opens (its
  Terminal panel). macOS gives camera permission to the app that launched
  the process, and an agent's own shell has none.

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `internal/tools/boopctl bridge` plus
  `Boop --headless --state-dir DIR --link usb:SOCKET`
  ([documentation/VERIFICATION.md](documentation/VERIFICATION.md) L4). Ask the owner to run
  `make run` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories, and give
  the installers `--home` too: `NSHomeDirectory()` ignores `HOME`.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless the owner asks** (below).

## Architecture rules

The full picture is in [documentation/ARCHITECTURE.md](documentation/ARCHITECTURE.md), and
how Boop sits on its three packages (agent-hooks, JHarness, LinkKit) in
[documentation/MODULES.md](documentation/MODULES.md). The rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Actions (`mood`, `react`) carry out effects and check their own rules.
- **Everything goes through the transcript.** Hooks, pokes, heartbeats
  and every action are raw events in one shape; the view folds them into
  what the brain hears ([documentation/harness/EVENTS.md](documentation/harness/EVENTS.md)).
  Anything else is a log line.
- **The packages stay apart.** agent-hooks, JHarness and LinkKit know
  nothing of Boop or of each other.
  Boop translates between them in a few places (documentation/MODULES.md, Where
  they join), and anything Boop-specific stays in `app/` or `firmware/`.
- **The harness is generic.** JHarness takes events, asks every output's
  questions in one request and hands each output its own answers. It
  never reads an event's facts, picks what Boop says or talks to the
  device.
- **Only Voice knows what Boop can say.** Only the memory store reads and writes
  the memory files. Only LinkKit knows Bluetooth or USB: on the Mac its
  `DeviceLink` and transports, with Boop's vocabulary on them in
  `app/BoopKit/DeviceLink/BoopDevice.swift`; on the board its device
  library, which `firmware/src/main.cpp` feeds the serial port's lines.
- **The brain is never on the screen's path.** Rules keep the screen true
  at once (the look, "needs you", the tap's poke, the rules' one-shots).
  Every reaction, a finished turn's included, is the brain's, later or
  not at all.
- **The brain is Jev: multiple choice only.** It answers questions about
  a plain-text state; there's no free text. Keep questions few, with
  options that say what they're not.
- **The steering files are read-only at runtime.** `documentation/steering/` is
  the single source, and the app bundles it at build time
  (`Package.swift` copies it into the app's resources).
- **No code, commands, tool output, file contents or agent transcripts go
  to the brain.** The only words are your prompt, the agent's last
  message and what you say to Boop on push-to-talk, cut short.
- **"Needs you" and the screen priority are plain rules in the core.**
- **The device renders, reports, and decides when a request plays**
  (LinkKit's turn), never what Boop does: the Mac sends each thing to
  play at once and never times it. It receives the same messages over
  Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.

## Specs stay in sync

`documentation/` is the contract. A change to behaviour, a message, a budget, a
flow, a command or a check updates the matching spec in the same commit,
so reviewers can read the spec diff next to the code diff.

**Start from the latest code.** In a worktree, check that
`git log --oneline HEAD..main` prints nothing before you compare or edit
anything: a worktree made from `origin/main` can be far behind an
unpushed local `main`.

**Which spec goes with which code** (specs are in `documentation/`; a package's
`SPEC.md` and `README.md` are in its own folder):

| When you change | Update |
| --- | --- |
| `app/BoopKit/Core/Core.swift`, `app/BoopKit/Core/Activity.swift`, `app/BoopKit/Core/Growth.swift`, `firmware/src/app/behaviour.*` | `BEHAVIORS.md` |
| `firmware/src/render/`, `firmware/src/app/gesture.*` | `DEVICE.md` |
| `agent-hooks/` (its sources, tests, fixtures and command line) | `agent-hooks/SPEC.md`, `agent-hooks/README.md`, and `ADAPTERS.md` where Boop's use changes |
| `jharness/` (its sources, tests, `jharness-emit` and Beacon) | `jharness/SPEC.md`, `jharness/README.md`, and `harness/HARNESS.md` §1.1 where Boop's use changes |
| `linkkit/Sources/` (the bridge included), `linkkit/Tests/`, `linkkit/Package.swift` | `linkkit/SPEC.md`, `linkkit/README.md`, `ARCHITECTURE.md` §3.7 and §10, and `PROTOCOL.md` where Boop's use changes |
| `linkkit/device/` (its tests and `platformio.ini` included) | `linkkit/SPEC.md`, `linkkit/device/README.md`, `DEVICE.md` |
| How the pieces join: the adapter, the pipeline's batch, the runtime's link calls, `Reactions`, which package products Boop takes | `MODULES.md` |
| `app/BoopKit/Adapters/`, the hook setup in `app/Boop/MenuBarApp.swift` | `ADAPTERS.md` |
| `app/BoopKit/Harness/`, `app/BoopKit/Brains/`, `app/BoopKit/App/Pipeline.swift` | `harness/HARNESS.md` |
| `app/BoopKit/Core/Event.swift`, `app/BoopKit/Core/TranscriptView.swift`, what the core records | `harness/EVENTS.md` |
| `app/BoopKit/Presence/`, `app/Boop/PresenceSignals.swift` | `harness/EVENTS.md` §2.1 |
| `app/BoopKit/Actions/`, `documentation/steering/` | `harness/DECISIONS.md` |
| `app/BoopKit/App/Reactions.swift` (how a reaction's `ended` reads) | `harness/DECISIONS.md` §5 |
| `app/BoopKit/Memory/`, `app/BoopKit/App/` | `ARCHITECTURE.md` §3–4 |
| `app/BoopKit/Voice/`, `firmware/src/voice/`, `firmware/src/app/effect_track.*`, `internal/tools/voicegen/`, `internal/tools/sfxgen/` | `VOICE.md` |
| `app/BoopKit/DeviceLink/`, `app/BoopKit/Core/StateSnapshot.swift`, `app/BoopKit/Actions/DeviceMoment.swift`, `firmware/src/app/device.*`, `internal/tools/boopctl_lib/` | `PROTOCOL.md` |
| `firmware/src/board/`, `firmware/platformio.ini`, `internal/tools/fontgen/` | `DEVICE.md` |
| `internal/tools/facegen/` (and its designs), `firmware/src/render/scene.*` | `DEVICE.md` §6 |
| `internal/boop-design/boop-sound-bank-v4/` (the designs and their sounds) | `DEVICE.md` §6, `VOICE.md` §10 |
| `Makefile`, `internal/Makefile`, `internal/tools/`, `internal/app/BoopDev/`, `internal/skills/`, tests | `VERIFICATION.md`, this file, `README.md` |
| `internal/app/Boop/` (`--headless`, `--snapshots`), `internal/app/BoopDevKit/Replay.swift`, `internal/firmware/sim/`, `internal/firmware/test/` | `VERIFICATION.md` |
| `internal/tools/boopctl_lib/dash/`, the dev lines and the dashboard's lines in `debug.jsonl` | `harness/HARNESS.md` §9 |
| `internal/tools/boopctl_lib/day.py`, or any `debug.jsonl` line it reads | `harness/HARNESS.md` §9 (A day's summary), `VERIFICATION.md` §2 |
| `internal/app/BoopDevKit/Eval/`, `internal/app/Evals/`, `internal/tools/boopctl_lib/workday.py` | `EVALS.md` |
| `Package.swift`, a package's `Package.swift` (`agent-hooks/`, `jharness/`, `linkkit/`), what goes in `internal/` | `ARCHITECTURE.md` §10, `internal/README.md`, `MODULES.md`, this file |
| Structure, boundaries or a budget | `ARCHITECTURE.md` |
| What's in or out of v1 | `VISION.md` (Scope) |
| A spec added, renamed or removed | `documentation/README.md`, this table |

**Rules that keep them from drifting:**

- **Say each fact once.** A number, name or rule lives in one doc; the
  others link to it. When you change one, grep `documentation/`, this file,
  `README.md`, `internal/README.md`, `internal/skills/`,
  `internal/tools/*/README.md`, `agent-hooks/*.md`, `jharness/*.md`,
  `linkkit/**/*.md` and code comments for the old value or name, and fix
  every hit. Most drift is a copy left behind in a second
  doc.
- **Examples are real.** JSON, command lines and file layouts in a spec
  come from a test fixture or actual output. When the shape changes, the
  example changes with it.
- **Commands run as written.** Every command in this file, `README.md`,
  `VERIFICATION.md`, `MODULES.md`, `agent-hooks/README.md`,
  `jharness/README.md`, `linkkit/README.md`, `linkkit/device/README.md`
  and the skills exists with those arguments. When you
  add, rename or remove a make target, a `boopctl` or `boopdev`
  subcommand, a flag or a path, grep the docs for it in the same commit.
- **Pin rules in tests.** When you implement or change a rule with a number
  in it (a timing, cap, threshold or priority), add or update a test that
  checks it and names the spec section.
- **Removed code takes its docs with it.** Delete any doc, skill, checklist or code comment that describes code that's
  gone.
- **Dates move with the work.** Bump the "Updated" date on every spec
  you touched. Tell the owner about drift you find but don't fix.
- **Before you commit,** go through `git diff --stat` against the table
  above, check that `cmp CLAUDE.md AGENTS.md` is silent, and check that
  new or edited links resolve.

If a change deliberately departs from the spec, change the spec first and
add a row saying why to the decision log at the end of
[documentation/ARCHITECTURE.md](documentation/ARCHITECTURE.md).

## Checking your work

Check changes with the loop in [documentation/VERIFICATION.md](documentation/VERIFICATION.md)
§1, and report only checks that actually ran and passed. Evidence goes in
`documentation/evidence/<date>-<topic>/` (§7 there).

Before trusting anything that depends on hooks, run the `doctor` skill
(`internal/skills/doctor/doctor.sh`). It checks that this agent's hooks
reach Boop; `--headless` checks against a throwaway headless app instead
of the owner's.

**Webcam.** Webcam verification is opt-in. Use the `webcam-verify` skill
only when the owner asks for it and confirms the board is set up for that
session. Clips are bounded and video only, and raw footage stays local and
out of git.
