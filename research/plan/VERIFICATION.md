# Verification

Status: first draft, 2026-09-08. How an agent verifies its own work on every
part of Boop, autonomously, and how we make sure no regression ships.
Companion to `ARCHITECTURE.md`. The current command reference is
`research/archived/eng/TESTING.md`; this document says what the v1 verification
system should be and what is missing today.

---

## 0. Goal

An agent should be able to change any part of the system (hook script,
server, extractor, reducer, store, voice, desktop, wire, firmware) and prove
the change works without a human in the loop, using the same tools a human
would. "Prove" means: the right layer of the pyramid is green, and for
anything visible, there is a picture.

Two constraints shape everything:

- **The Mac app must be launched by the user,** not the agent. An
  agent-launched Boop aborts on the Bluetooth permission prompt. Every
  test that needs the app running says so up front and checks `/healthz`
  before doing anything else.
- **The device must be plugged in over USB with the app quit** for
  hardware tests, because the firmware has no serial-versus-BLE
  arbitration and the app's keepalives overwrite injected state.

---

## 1. The pyramid for this repo

| Layer | What it proves | Tool | Needs | Speed |
| --- | --- | --- | --- | --- |
| **Unit** | Reducer transitions, moments, cheer sizing, nudge timing; extractor readers over fixture windows; stakes and gloss rules; wire encoder byte caps; hook installer against temp dirs | `swift test --filter …` | Xcode toolchain | seconds |
| **Integration** | Server plus engine in-process: real HTTP routes, auth, approval continuations, MCP; engine plus outputs with a fake transport | `swift test --filter EngineIntegrationTests,HookServerBehaviorTests,MCPServerTests` | Xcode toolchain | seconds |
| **Visual, app** | Every state of the menu bar creature and popover as PNG | snapshot harness | opt-in flag | seconds |
| **End to end, hooks** | The installed script, the running app, and every event per agent, with synthetic payloads | `app/tools/e2e-smoke.sh` and `app/tools/e2e/<agent>.sh` | app running | a minute |
| **Live harness** | This harness's own hooks reach Boop | `tools/doctor.sh` and `--confirm` | app running, agent in a harness | seconds |
| **Device, USB** | Firmware parse, model, render, buttons, timing, hardening | `make hil` | device on USB, app quit | minutes |
| **Visual, device** | The real screen, state by state and posture by posture | `buddyctl screenshot` and the contact sheet (§2.1) | device on USB | seconds each |
| **Device, BLE** | The production transport, bonding, prompt round trip | `make hil-ble` | paired device | minutes |
| **Soak** | Heap floors, reboot cycles, serial fuzz, watchdog | `test_hardening.py` with `BUDDY_SOAK_CYCLES` | device on USB | up to an hour |

The rule: **test at the lowest layer that can catch the bug, and add one
test at the layer above to prove the wiring.** A cheer-sizing bug is a
reducer unit test, never a hardware test. A byte-cap bug is a wire encoder
test plus one HIL screenshot that shows Korean text rendering.

---

## 2. What an agent can verify, by area

### 2.1 The device

The loop an agent uses to tweak the UI on real hardware:

```sh
cd firmware/esp32
pio run -e <env> -t upload                      # flash
python3 tools/buddyctl.py ping --json           # alive, build id, heap
python3 tools/buddyctl.py set --pet attention --waiting 1 \
    --prompt-id req_1 --prompt-tool Bash --prompt-hint "npm test"
python3 tools/buddyctl.py expect --pet attention --prompt-id req_1 --json
python3 tools/buddyctl.py screenshot --out /tmp/attention.png --scale 2
# read /tmp/attention.png, judge it, edit face code, repeat
python3 tools/buddyctl.py press a --ms 150 --json   # the decision
```

The agent reads the PNG directly and judges it against `UX-DEVICE.md`.
This works today for the current firmware's state vocabulary.

What v1 needs on top:

- **`buddyctl frame --json '<RenderState v2>'`.** Inject a raw frame so
  every v2 field (state, effort, cheer, card, bubble, dots, snap,
  cosmetic) is drivable without a flag per field.
- **Contact sheet.** `tools/shots.sh` renders the six states, three cheer
  sizes, three effort levels, the card at each stakes level, a bubble with
  Korean text, and each posture, into one labeled grid PNG. An agent
  attaches it to every firmware change that touches rendering. A human can
  review twenty screens in one glance.
- **Golden screenshots.** The contact sheet's cells checked into a
  fixtures directory, compared in HIL with a perceptual threshold and a
  time-frozen render (`buddyctl set --t <ms>` so springs and blinks are
  deterministic). A diff fails the test and writes the before, after, and
  diff images for the agent to look at.
- **Posture and motion injection.** `buddyctl inject imu --posture perch`
  and `--shake` so posture sets and motion reactions are testable without
  tilting anything.
- **Outbound assertions.** `buddyctl listen` already prints device-to-host
  lines; HIL asserts `decision`, `collect`, `posture`, `battery` for each
  input.

### 2.2 The Mac app

Today: unit and integration tests run without the app, the snapshot harness
renders the SwiftUI views to PNG, and the e2e suite drives a running app
over HTTP. The gap is that the agent cannot start the app.

What v1 needs:

- **A headless mode.** `swift run Boop --headless` (or an env var) starts
  the server, engine, and outputs with Bluetooth and the status item
  disabled. No TCC prompt, so an agent can launch it, run e2e, and quit it.
  The desktop output still renders to an offscreen buffer so snapshots come
  from the same code path as the real UI.
- **`GET /diag/recent?n=50`.** The engine already keeps a ring buffer of
  hook, approve, signal, and engine entries. Expose it read-only on
  localhost with the token, so e2e and the doctor can assert "an event from
  source X with name Y arrived," not just "the version moved."
- **`GET /state`** for tests only, behind the token and a debug flag: the
  full `BuddyState`. The e2e suite today can only assert version deltas
  because pet state is not exposed; with this it asserts the six states,
  effort, cheer size, and the card directly.
- **Snapshot isolation.** The harness writes into the shared defaults
  domain and poisons the next run; fixed by a scratch suite (already in
  `research/archived/TODOs.md`).

With those, an agent's app loop is: `swift test`, launch headless, run
`e2e-smoke.sh`, read `/state` at each step, snapshot, quit.

### 2.3 Hooks

Three questions, three layers.

**Is the installer right?** `HookInstallerTests` against temp home
directories: install, verify, repair, uninstall, for each agent, and
idempotence on a second install. Plus a test that the generated script is
byte-identical to the fixture, so script changes are deliberate.

**Does the script deliver what the app expects?** The e2e suite per agent
posts synthetic payloads through the real route and asserts the outcome.
v1 extends it to post through the installed script itself (as the doctor
does), so the script's parsing, timeouts, and fail-open paths are exercised,
including: app down (script must exit 0 fast), bad token (exit 0), approval
with app down (returns passthrough).

**Are the payloads still what we think they are?** Agents ship weekly and
have shipped hook regressions. Two guards:

- A **fixture corpus** under `app/Tests/Fixtures/hooks/<agent>/<version>/`
  of real payloads, one per event, recorded with `tools/record-hooks.sh`
  (a wrapper script that tees the raw payload, redacts paths and text, and
  writes it as a fixture). The extractor's unit tests replay these. When a
  new agent version ships, record a new directory; if the readers degrade,
  the test says which field moved.
- A **contract check** that diffs the event names and fields we depend on
  against the reference captures in `research/archived/eng/reference/`, and fails
  when a capture is updated and a field we use disappears.

**Is this harness firing right now?** The doctor (§3).

### 2.4 The app and the device together

`make hil-ble` after pairing covers the production transport. v1 adds one
scripted scenario that runs the whole path: the e2e suite raises a prompt
through the hook script, `buddyctl ble listen` sees the card frame, a
synthetic press answers it, and the held hook call returns allow. That is
the needs-you flow measured end to end with timestamps at each hop, which
is how the latency budgets in `ARCHITECTURE.md` get numbers.

---

## 3. The doctor: self-diagnosis in any harness

An agent working in Claude Code, Codex, or Cursor should be able to ask
"is Boop seeing me?" and get a true answer. The answer is a shell script,
so it works in every harness, and a skill file per harness that tells the
agent how to drive it.

**Files.**

| Path | Role |
| --- | --- |
| `tools/doctor.sh` | The truth. Bash, no dependencies beyond curl and python3. |
| `skills/doctor/SKILL.md` | The canonical skill: procedure, exit codes, fixes. |
| `.claude/skills/doctor`, `.codex/skills/doctor`, `.cursor/skills/doctor` | Symlinks to the canonical skill so each harness discovers it by its own convention. |
| `AGENTS.md` and `CLAUDE.md` | One line pointing at the script, for harnesses that read instructions but not skills. |

**What it checks, in order.** Config and token; the installed hook script;
hook registration for the detected harness (or all three); the app at
`/healthz`; that an unauthenticated hook is rejected and an authenticated
one accepted; a synthetic session start and end sent through the installed
script, asserting the state version moved; optionally a device ping.

**The live step.** Nothing a script does can make the harness fire its own
hooks. So the doctor arms: it waits for the state version to settle and
records it. The agent then runs one harmless tool call in its own harness
(`echo BOOP_DOCTOR_PING`), and `tools/doctor.sh --confirm` checks that the
version moved. Exit 0 means the harness is wired. Exit 1 with the static
checks green means the harness's hook config is stale or the harness was
started before hooks were installed, and the skill says what to do.

**Exit codes.** 0 healthy, 1 broken, 2 armed and waiting for confirm.

**Harness detection** is best effort from environment variables and can be
overridden with `--agent`. The detection hints for Codex and Cursor need
verifying against those harnesses; until then `--agent` is the reliable
path and the skill says so.

**Once `/diag/recent` exists,** the confirm step asserts an entry with the
harness's source name instead of a version delta, which removes the one
flake (a background tick moving the version).

Verified today: the static checks run and report correctly with the app
down. The live round trip and confirm were not exercised in this session
because the app was not running.

---

## 4. Regression gates

**Every pull request** (CI, no hardware, under five minutes): build,
`swift test` in full, extractor fixture replay, wire encoder byte-cap tests,
snapshot harness, lint, and the firmware builds for every environment. Red
means no merge. CI pins the Xcode version so lint and test output do not
drift with the runner.

**Before every release** (a human's Mac and a plugged-in device, under an
hour): the packaged-app smoke, the e2e suite per agent against the real
app, `make hil` including hardening, `make hil-ble`, the contact sheet
attached to the release notes, and the doctor run from each harness.

**Nightly, when the hardware is on the bench:** the soak at high cycle
counts and the end-to-end latency scenario, with numbers posted to a sheet.

**Rules.**

- A firmware change that touches rendering ships with a contact sheet in
  the pull request. A reviewer looks at pictures, not diffs of face code.
- A server, extractor, or installer change ships with a fixture or an e2e
  case that would have failed before the change.
- A wire contract change bumps the version field and adds a compatibility
  test against the previous firmware's parser.
- A new agent version gets a fixture directory before we claim support.

---

## 5. How an agent works on this repo

The operating procedure, so autonomous work has a definition of done.

1. Run `tools/doctor.sh` at the start if the task touches hooks, the
   server, or anything that needs the app. Fix or report before continuing.
2. Make the change at the lowest layer it belongs to. Write or update the
   test at that layer first.
3. `make build` and the targeted `swift test --filter` for the area, then
   the full `swift test`.
4. If the change touches the server, extractor, or installer: ask the user
   to launch Boop (or use headless mode once it exists), then run
   `app/tools/e2e-smoke.sh` and read `/diag/recent`.
5. If the change touches firmware: flash, `make hil`, then the contact
   sheet, then look at every cell against `UX-DEVICE.md`. Attach the sheet.
6. If the change touches the wire: run both the encoder tests and one HIL
   screenshot with the longest allowed strings, including Korean.
7. Report what was run, what passed, what was skipped and why, with the
   pictures. Never describe a test as run if it was not.

Definition of done by area:

| Area | Done when |
| --- | --- |
| Reducer, moments, cheer | Unit tests cover the new transition and one integration test proves it reaches `BuddyState` |
| Extractor | Fixture replay passes for every agent and the new reader has a fixture that fails without it |
| Server, installer | Unit plus e2e case; doctor passes from at least one harness |
| Voice | Golden line test, post-filter test, fallback-on-timeout test |
| Desktop | Snapshot for every affected state, reviewed |
| Wire | Encoder tests, version bump if fields changed, compatibility test |
| Firmware | HIL green, contact sheet reviewed, heap floors held |

---

## 6. What to build, in order

1. **`/diag/recent` and `/state`** behind the token. Small, unblocks
   precise e2e and a flake-free doctor confirm.
2. **Headless app mode.** Unblocks agents running e2e on their own.
3. **`buddyctl frame` and the contact sheet.** Unblocks agent-driven UI
   tweaking on the v2 vocabulary.
4. **Golden screenshots with time-frozen render** in HIL.
5. **Hook fixture recorder and corpus**, then the extractor tests on top.
6. **End-to-end latency scenario** over BLE.
7. **CI pin and lint gate.**

---

## 7. Findings from the survey

- The repo's `.cursor/hooks.json` points at `bun run src/src/cli/index.ts`,
  which does not exist in this repository. It looks copied from another
  project and will fail closed-open silently in Cursor. Replace it with the
  installer's output or delete it.
- The e2e suite can only assert version deltas because state is not
  exposed over HTTP. Item 1 above fixes this.
- The doctor's harness detection for Codex and Cursor is unverified.
- The snapshot harness poisons the shared defaults domain (tracked in
  `research/archived/TODOs.md`).
