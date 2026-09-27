# Boop Agent Instructions

These instructions apply to the whole repo. `CLAUDE.md` and `AGENTS.md`
are the same file: edit `CLAUDE.md`, then copy it over `AGENTS.md`.

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
| `plan/` | The spec, which the code implements ([the index](plan/README.md)). [plan/PLAN.md](plan/PLAN.md) has the status and open items, and [plan/VERIFICATION.md](plan/VERIFICATION.md) how everything is checked. Evidence goes in `plan/evidence/` |
| `app/` | Swift package: the Mac menu-bar app, the `boop-hook` hook client, and the `boopdev` dev CLI |
| `firmware/` | PlatformIO firmware for the MicroTech MTR024QV01A board ([plan/DEVICE.md](plan/DEVICE.md)), with its simulator and unit tests built for the Mac (env `native`) |
| `tools/` | `boopctl` (device tool), `voicegen` (voice assets), `fontgen` (the device's fonts), `webcam/` (opt-in recorder) |
| `skills/` | `doctor` (hook self-check) and `webcam-verify`, symlinked for Claude, Codex and Cursor |
| `landing/` | The Next.js landing page (Vercel project root) |
| `archived/` | History only: research, docs, the gen-2 specs (`plan-gen2/`) and case model, and the finished v1 build plan with its full decision log (`plan-v1-build/`). Earlier code is at git tag `gen2-final` (`git show gen2-final:<path>`). Don't extend it |

Delete code that nothing uses; git keeps it.

## Commands

The everyday entry points are in [README.md](README.md), which stays a
short overview. Every make target and tool is in
[plan/VERIFICATION.md](plan/VERIFICATION.md) §2, and each CLI prints its
flags with `--help`. `make run` and `make debug` use Bluetooth, so they're
the owner's. For agents:

```sh
make build                                                # Mac app, boop-hook and boopdev (make test and make eval build too)
app/.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth, printing everything
app/.build/debug/Boop --snapshots DIR                     # the popover's panes and the menu-bar icons as PNGs, then exits
```

## Environment notes

- There's no Xcode, so `swift test` runs nothing. `make test` runs
  `python3 app/tools/test.py`, which generates the XCTest shim's runner,
  builds the package in one `swift build` and runs
  `app/.build/debug/BoopTests`.
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
  `/dev/cu.usbserial-*`, and the serial port needs no special permissions.
- System Python has no pyserial or Pillow. The tools use `tools/.venv`,
  which `tools/boopctl` makes on its first run (`make tools` refreshes it).
- A Unix socket's path has room for 103 bytes, so give `Boop --headless`
  a short state directory (under `/tmp`) or a short `--socket`.
- Webcam recording works only from a terminal the Claude app opens (its
  Terminal panel). macOS gives camera permission to the app that launched
  the process, and an agent's own shell has none.

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `tools/boopctl bridge` plus
  `Boop --headless --state-dir DIR --link usb:SOCKET`
  ([plan/VERIFICATION.md](plan/VERIFICATION.md) L4). Ask the owner to run
  `make run` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless the owner asks** (below).

## Architecture rules

The full picture is in [plan/ARCHITECTURE.md](plan/ARCHITECTURE.md). The
rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Actions (`mood`, `react`) carry out effects and check their own rules.
- **The harness is generic.** It records events, asks every action's
  questions in one request and hands each action its own answers. It
  never reads an event's facts, builds Minion speech, writes files or
  talks to the device.
- **Only Voice knows Minion speech.** Only the memory store reads and writes
  the memory files. Only the device link knows Bluetooth or USB.
- **The brain is never on the event path.** Rules give the immediate
  reaction, and the brain adds character later or not at all.
- **The brain is Jev: multiple choice only.** It answers questions about
  a plain-text state; there's no free text. Keep questions few, with
  options that say what they're not.
- **The steering files are read-only at runtime.** `plan/steering/` is
  the single source, and the app bundles a copy in
  `app/Boop/Resources/steering/`.
- **No code, file contents, prompts or agent transcripts go to the brain.**
- **"Needs you" and the screen priority are plain rules in the core.**
- **The device only renders and reports.** It receives the same messages
  over Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.

## Specs stay in sync

`plan/` is the contract. A change to behaviour, a message, a budget, a
flow, a command or a check updates the matching spec in the same commit,
so reviewers can read the spec diff next to the code diff.

**Start from the latest code.** In a worktree, check that
`git log --oneline HEAD..main` prints nothing before you compare or edit
anything: a worktree made from `origin/main` can be far behind an
unpushed local `main`.

**Which spec goes with which code** (specs are in `plan/`):

| When you change | Update |
| --- | --- |
| `app/BoopKit/Core/`, `firmware/src/app/behaviour.*` | `BEHAVIORS.md` |
| `app/Boop/`, `firmware/src/render/`, `firmware/src/app/gesture.*` | `UX.md` |
| `app/HookWire/`, `app/BoopHook/`, `app/BoopKit/Adapters/`, `app/BoopKit/Install/` | `ADAPTERS.md` |
| `app/BoopKit/Harness/`, `app/BoopKit/Brains/` | `harness/HARNESS.md` |
| `app/BoopKit/Core/Event.swift` | `harness/EVENTS.md` |
| `app/BoopKit/Actions/`, `plan/steering/` | `harness/DECISIONS.md` (and the app's copy of `plan/steering/`) |
| `app/BoopKit/Memory/`, `app/BoopKit/App/` | `ARCHITECTURE.md` §3–4 |
| `app/BoopKit/Voice/`, `firmware/src/voice/`, `tools/voicegen/` | `VOICE.md` |
| `app/BoopKit/DeviceLink/`, `StateSnapshot.swift`, `firmware/src/link/`, `firmware/src/app/{device.cpp,packets.h,link_silence.h}`, `tools/boopctl_lib/` | `PROTOCOL.md` |
| `firmware/src/board/`, `firmware/platformio.ini`, `tools/fontgen/` | `DEVICE.md` |
| `Makefile`, `tools/`, `app/BoopDev/`, `skills/`, tests | `VERIFICATION.md`, this file, `README.md` |
| `app/BoopKit/Eval/`, `app/Evals/` | `EVALS.md` |
| Structure, boundaries or a budget | `ARCHITECTURE.md` |
| What's in or out of v1 | `VISION.md` (Scope), `FUTURE.md` |
| A milestone's status | `PLAN.md` (its status table) |
| A spec added, renamed or removed | `plan/README.md`, this table |

**Rules that keep them from drifting:**

- **Say each fact once.** A number, name or rule lives in one doc; the
  others link to it. When you change one, grep `plan/`, this file,
  `README.md`, `skills/`, `tools/*/README.md` and code comments for the
  old value or name, and fix every hit. Most drift is a copy left behind
  in a second doc.
- **Examples are real.** JSON, command lines and file layouts in a spec
  come from a test fixture or actual output. When the shape changes, the
  example changes with it.
- **Commands run as written.** Every command in this file, `README.md`,
  `VERIFICATION.md` and the skills exists with those arguments. When you
  add, rename or remove a make target, a `boopctl` or `boopdev`
  subcommand, a flag or a path, grep the docs for it in the same commit.
- **Pin rules in tests.** When you implement or change a rule with a number
  in it (a timing, cap, threshold or priority), add or update a test that
  checks it and names the spec section.
- **Removed code takes its docs with it.** Delete, or move to `archived/`,
  any doc, skill, checklist or code comment that describes code that's
  gone.
- **Status moves with the work.** When a milestone or task closes, update
  its row in `PLAN.md`, link its evidence from there, and bump the
  "Updated" date on every spec you touched. Drift you find but don't fix
  goes in `PLAN.md` as an open item.
- **Before you commit,** go through `git diff --stat` against the table
  above, check that `cmp CLAUDE.md AGENTS.md` is silent, and check that
  new or edited links resolve.

If a change deliberately departs from the spec, change the spec first and
add a row saying why to the decision log at the end of
[plan/ARCHITECTURE.md](plan/ARCHITECTURE.md).

## Checking your work

Check changes with the loop in [plan/VERIFICATION.md](plan/VERIFICATION.md)
§1, and report only checks that actually ran and passed. Evidence goes in
`plan/evidence/<date>-<topic>/` (§7 there), linked from `PLAN.md`.

Before trusting anything that depends on hooks, run the `doctor` skill
(`skills/doctor/doctor.sh`). It checks that this agent's hooks reach Boop;
`--headless` checks against a throwaway headless app instead of the
owner's.

**Webcam.** Webcam verification is opt-in. Use the `webcam-verify` skill
only when the owner asks for it and confirms the board is set up for that
session. Clips are bounded and video only, and raw footage stays local and
out of git.
