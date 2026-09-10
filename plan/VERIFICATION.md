# Verification

Status: first draft, 2026-09-08. How an agent verifies its own work on every
part of Boop, autonomously, and how we make sure no regression ships.
Companion to `ARCHITECTURE.md`. The current command reference is
`archived/research/eng/TESTING.md`; this document says what the v1 verification
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
| **End to end, hooks** | The installed script, the running app, and every event per agent, with synthetic payloads | `archived/app/tools/e2e-smoke.sh` and `archived/app/tools/e2e/<agent>.sh` | app running | a minute |
| **Live harness** | This harness's own hooks reach Boop | `skills/doctor/doctor.sh` and `--confirm` | app running, agent in a harness | seconds |
| **Device, USB** | Firmware parse, model, render, buttons, timing, hardening | `make hil` | device on USB, app quit | minutes |
| **Visual, device** | The real screen, state by state and posture by posture | `buddyctl screenshot` and the contact sheet (§2.1) | device on USB | seconds each |
| **Motion, webcam** | Physical display motion over time, with capture-quality limits | `make webcam`, [workflow](../tools/webcam/README.md) | Mac camera permission, Buddy facing lens; USB injection requires app quit | 3–60 second clips |
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
cd archived/firmware/esp32
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

### 2.1.1 Webcam motion verification (2026-09-10)

Implemented in `tools/webcam/`: native macOS video-only capture, explicit camera
selection, bounded duration, and offline analysis of consecutive video frames.
The [workflow](../tools/webcam/README.md) covers framing, USB and natural BLE
scenarios, live presentation clocks, cropping, and review against `UX-DEVICE.md`
§20. This layer is explicit opt-in only, via `webcam-verify` or an explicit webcam
request plus physical setup confirmation for the current session. It is not a
required step for ordinary animation changes and must not start automatically.
Prior setup does not authorize future sessions; normal tests remain independent.

Evidence consists of the original MOV and capture settings, a full-resolution framing preview, timestamped cropped
sequence sheets retaining every frame in the selected interval, frame timestamps
CSV, a capture-cadence report, and a reviewer-authored motion assessment. The
report always starts **unreviewed**; clean timestamps do not automatically prove
fluidity. Inspect the full motion and settling, record the usable frame rate and
focus, and distinguish camera artifacts from firmware faults. If the agent can
only inspect image sequences, disclose the absence of real-time playback.

Human setup: point the Buddy screen at the camera and allow camera access once.
Quit Boop only for injected USB scenarios. No microphone is captured, no device
flash is required, and raw camera footage stays local by default. A fresh output
directory is mandatory to prevent evidence replacement.

`make webcam-test` exercises a synthetic moving-square video with a deliberate
missing frame, temporal interval selection, consecutive-frame preservation,
invalid inputs, and overwrite protection. Live camera/Buddy review is a separate gate. The first physical run is recorded
in [the 2026-09-10 review](evidence/webcam/2026-09-10.md): capture and temporal
review worked, with explicit limits on motion certification.

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
  `archived/research/TODOs.md`).

With those, an agent's app loop is: `swift test`, launch headless, run
`e2e-smoke.sh`, read `/state` at each step, snapshot, quit.

### 2.3 Hooks

Phase 3 cleanup: `HookFixtureTests` replays the Claude tenth-try capture for
both Claude Code and Codex; Cursor keeps its distinct capture. `HookPayloadTests`
checks v6 transport caps and the Python-free pre-tool path; `ExtractorPrivacyTests`
checks tallies, closing-line retention, and every UI/diagnostic/fact surface.

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
  against the reference captures in `archived/research/eng/reference/`, and fails
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
| `skills/doctor/doctor.sh` | The truth. Bash, no dependencies beyond curl and python3. Lives inside the skill so the skill is self-contained. |
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
(`echo BOOP_DOCTOR_PING`), and `skills/doctor/doctor.sh --confirm` checks that the
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

Verified 2026-09-08 with Phase 0 landed: static checks, the synthetic
round trip, and the live arm-and-confirm all pass from inside Claude Code
against a headless app, with the confirm reading the harness's own
PostToolUse entry from `/diag/recent`.

---

## 4. Regression gates

**Intended pull-request checks** (run locally or manually dispatch CI; automatic
CI is disabled as of 2026-09-10): build,
`swift test` in full, extractor fixture replay, wire encoder byte-cap tests,
snapshot harness, lint, and the firmware build for the shipping board
(`ws-amoled164`; the M5 environments are archived hardware). Red
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

1. Run `skills/doctor/doctor.sh` at the start if the task touches hooks, the
   server, or anything that needs the app. Fix or report before continuing.
2. Make the change at the lowest layer it belongs to. Write or update the
   test at that layer first.
3. `make build` and the targeted `swift test --filter` for the area, then
   the full `swift test`.
4. If the change touches the server, extractor, or installer: ask the user
   to launch Boop (or use headless mode once it exists), then run
   `archived/app/tools/e2e-smoke.sh` and read `/diag/recent`.
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
  `archived/research/TODOs.md`).

**Phase 4 notes (2026-09-09).** SQLite schema 1 uses WAL: `facts` (typed payload JSON plus kind/session/project/epoch-ms/local-day), `profile`, `traits` (including bond), append-only `ledger` (source quantities; weights and caps applied when read), `inventory`, `meta`, SQL-readable per-key `memory`, and daily `drift`. Legacy memory is committed before `.migrated` renaming; an unreadable legacy file remains recoverable and does not disable SQLite. Numerical choices beyond UX-GROWTH: profile confidence starts at 0.6, rises by 0.1 per subsequent reflected day, and caps at 1.0; a dominant runner needs a strict majority (>50%, at least one observation), with lexical tie ordering; morning is 05:00–11:59, “many turns” is >=20 per session, “long quiet” is <=1 turn over >=60 minutes, and “many distinct tools” is >=5 per day. Each qualifying morning start/many-turn session adds 1 energy, each late-night moment subtracts 1; each denial/survived rate-limit moment adds 1 cheek and each long quiet session subtracts 1; each check-in/greet adds 1 warmth; each previously unseen project and a day with >=5 tools adds 1 curiosity, before the documented +/-3 caps. SQLite busy timeout is 5,000 ms and cosmetic POST bodies are capped at 1,024 bytes. Level-one defaults are skin `default`, accessory `none`, silhouette `default`; unlocks do not automatically replace equipped cosmetics. `xpNext` is remaining XP, `today` is today's XP, `daysTogether` counts active days, and rest days preserve but do not increment the active-day streak; rest accrual uses lifetime active-day count, and today is not a miss until tomorrow. Agent work and physical check-ins qualify for an active day; approvals never do. Nightly reflection processes the preceding local calendar day once, while the diagnostic trigger processes today once; repeat evidence on later days raises confidence. Project recurrence uses retained 30-day history. A session-end task is a fallback only when that session completed work but had no goal-pass task award. No token count is inferred from a transcript path alone; hook-carried per-message counts and Codex cumulative usage are supported, and missing counts/ Cursor token usage are skipped. The hook transport version is 7 to retain only numeric usage metadata. The existing 2-second maintenance timer checks idle/AC; reflection discards ephemeral closing lines after success. XP weights, level thresholds, streak/rest limits, bond increments, and unlock levels are unchanged from UX-GROWTH. Unknown local hour is represented internally by -1. Verification: clean HEAD baseline 352 passed / 4 socket-denied skips / 356 total; Phase 4 370 passed / the same 4 skips / 374 total, zero failures. `swift build --disable-sandbox --product Boop`, `swift build --disable-sandbox --product BoopSignal`, `python3 tools/gen-test-runner.py`, and `swift run --disable-sandbox BoopTests` each exited 0. Swift commands used `CLANG_MODULE_CACHE_PATH=/tmp/boop-p4-clang` and `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boop-p4-swift` because default cache writes and SwiftPM nested sandbox execution are denied by this host; the host sandbox remained enforced. `bash -n` on e2e/lib.sh plus claude.sh, codex.sh, and cursor.sh, and `git diff --check`, exited 0. All three tenth-try fixture replays award 36 XP with one task; persisted growth/memory survive restart. SQLite/WAL/shared-memory bytes passed the raw-text marker checks. Real HTTP e2e and the four localhost-dependent tests remain unexecuted here; no hardware or live nightly AC/idle run was performed. No frozen directories changed and no commit/push was made.

## Phase 5 notes

Implemented 2026-09-09 in `app/` only (plus this note).

- `Boop/Core/Voice/`: `Voice.swift` owns seeded bank selection, daily and
  last-20 exclusions, the one-second model race, and late-result rejection.
  `VoiceRuntime.swift` provides Null and conditionally compiled Foundation
  Models runtimes and structured prompt assembly. `VoiceFilter.swift` checks
  both authored and model lines before character-safe byte truncation.
  `VoiceBanks.swift` loads resources and substitutes bounded labels.
  `Recap.swift` assembles fact-only summaries.
- `Boop/Resources/voice/{en,ko}/`: 16 occasion files per language, each with
  earnest/wry/cheeky banks of 42 entries: **2,016 entries per language**.
  Each register has six core lines with seven short spoken lead-in variants.
  Banks cover seven moments, three cheer sizes, three uh-oh kinds, greeting,
  recap, and profile-line vocabulary.
- `BuddyEngine`, `BuddyEvent`, `BuddyReducer`, `BuddyState`, `DefaultsKey`, and
  `Clock`: asynchronous gift/bubble wiring, stale-response guards, recap
  delivery then sleep, and Sendable clock capture. `MomentLines` is deleted;
  the reducer no longer composes gift text from raw hints.
- `Store/Store.swift`: schema 3 adds `voice_recent` (last 20 returned lines)
  and `voice_day` (all returned lines today), a persisted recap-day marker,
  and Voice-assisted reflection. Rules still select facts, cap nights at five
  candidates, and supply the exact stored fallback on any failed rephrase.
- `Extractor/SessionWindow.swift` adds the structured `turnCompleted` fact;
  the reducer emits it. Recap counts completed turns and successful goal
  outcomes, uses the latest result per session/goal to count open goals, and
  sums completed-turn durations for hours. Legacy session summaries are used
  only when a session has no completed-turn facts, preventing double counts.
  The dominant project and biggest moment come from stored facts. Today's
  query is not limited to the diagnostic route's last 500 facts.
- `Server/HookServer.swift`: authenticated, headless-only `GET /state/recap`
  and `POST /diag/recap`. `Views/PopoverView.swift` displays the app paragraph.
  `tools/e2e/lib.sh` checks a nonempty <=40-byte tenth-try gift and forces/reads
  a recap with a nonempty <=63-byte device line and app paragraph.
- Tests: four new Voice/Recap test files, reflection rephrase/fallback tests,
  and adjusted reducer/engine/fixture assertions for asynchronous Voice.
  Generated runner updated.

Settings are read when constructing the engine: defaults `language` is `en`
(or `ko`); `voiceRuntime` is `auto` (or `off`). Auto uses the system model only
when the framework, OS version, and model availability permit it. No download
or new package dependency is needed.

Style/behavior decisions beyond UX-VOICE.md:

- Short, optional spoken lead-ins provide variation without changing facts
  or the selected register. Korean uses native polite-casual lines. Historical
  `first one!` loses its exclamation mark because first-ever is not necessarily
  a dance; the old two-sentence hard-won line becomes a single sentence.
- Generic error banks avoid claiming a build failed without build facts.
  Long project/file/agent labels are bounded; unsafe labels use neutral nouns.
- Emoji are rejected for app lines too (stricter than the allowed one).
  Sentence counts are capped at one for device lines and three for app text.
  Validation sees the entire bounded response before truncation, so a banned
  suffix cannot be hidden behind the byte cap. English single-word bans use
  word boundaries ("rent" must not reject "different"); negative phrases also
  resist spacing and punctuation changes.
- An exhausted finite bank is silent instead of repeating a line that day.
  Profile candidates are exempt from novelty selection: facts must retain
  their meaning, and reflection retains the original rule text on failure.
- The stop hour is inferred from the end of the longest typical activity
  block in the UTC histogram after conversion to local hours, including
  blocks crossing midnight; unknown histories use 18:00. Active work/cards
  keep priority if a recap finishes while a new interaction is arriving.
- There is at most one outstanding model generation per Voice actor,
  including when a runtime ignores cancellation. A late result is discarded;
  other calls use the authored floor while that generation is outstanding.

Verification (macOS CommandLineTools, Swift 6):

The initial unmodified `swift run BoopTests` exited 1 before project sources:
blocked user module-cache writes. Redirecting caches exposed SwiftPM's nested
`sandbox-exec` denial. Successful commands below use
`CLANG_MODULE_CACHE_PATH=/tmp/boop-clang` and
`SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boop-modules`, plus `--disable-sandbox` to
turn off SwiftPM's nested sandbox; the agent filesystem sandbox remains on.
No permission escalation was used.

| Command (from `app/`) | Exit | Result |
| --- | --- | --- |
| `swift build --disable-sandbox --product Boop` | 0 | Build passes, including FoundationModels conditional branch on this SDK |
| `swift build --disable-sandbox --product BoopSignal` | 0 | Build passes |
| `python3 tools/gen-test-runner.py` | 0 | 398 tests registered |
| `swift run --disable-sandbox BoopTests` | 0 | 394 passed, 4 skipped, 0 failures |
| `bash -n tools/e2e/lib.sh` | 0 | Shell syntax passes |
| `git diff --check` (repo root) | 0 | Clean |

The isolated HEAD baseline (archived with `git archive` into `/tmp`, using an
independent scratch build and the same cache/sandbox flags) exited 0 with
**375 passed, 4 skipped of 379**. After: **394 passed, 4 skipped of 398**
(+19 tests). The four skips in both runs are existing real-HTTP tests denied
localhost sockets. Bank tests validate all files and substituted device
lines, and draw 40 distinct lines for every device occasion/register/language.
Timing tests cover a three-second runtime and a cancellation-ignoring runtime;
both return the authored floor within 1.1 seconds. Fixture recap, Korean byte
caps, model rejection, profile fallback, persisted exclusions, stale prompt
suppression, repeat-model fallback, and midnight stop inference are covered.

Unexecuted here: shell HTTP e2e (including the new recap routes), the four
socket-dependent tests, real system-model inference/latency across Macs, and
physical Korean device rendering. No app or firmware was launched or flashed;
no hook-dependent claim is made. Model rephrases are stylistically filtered
and instructed to preserve facts; semantic fidelity of unconstrained model
text still needs the planned human/model-quality evaluation.
Phase 6 notes: firmware rituals, cosmetics, perch poses, pickup and all-state
session dots now have capture recipes and USB HIL assertions. The 18 new
cells settle at 4500 ms (first wake), 700 ms (greet 0–3), 450 ms (levelup and
streak), 300 ms (pickup), 600 ms (perch dance), and 2500 ms (remaining cells).
The host-only animation clock guard checks the new presentation paths.
Hardware flash, USB/BLE HIL, golden recording/review, idle heap floors,
retire frame latency and overnight battery verification remain unexecuted.


**Phase 8 firmware notes (2026-09-09).** The firmware half implements per-unit
NVS identity, `unit`/`sign`, real-clock rate limiting, retire key clearing,
identity-preserving `firstwake reset`, and USB debug regeneration via reboot.
The bundled ESP-IDF 5.5.4 / mbedTLS 3.6.5 lacks an Ed25519 pk type, so the
algorithm is P-256 ECDSA with SHA-256 (SEC1 public key, DER signature; details
in WIRE-V2). Keys are generated only in setup, using hardware-entropy-seeded
CTR-DRBG before HAL/RF initialization; a retired device needs reboot before
signing with a new identity. Offline `tools/pio_ws.sh run -e ws-amoled164`
passed: RAM 48,100 / 327,680 bytes (14.7%), Flash 1,269,531 / 6,291,456 bytes
(20.2%). The requested three-file Python compile check and four host-only
verification/CLI tests passed using the available Python with cryptography 50.0.1.
USB/BLE HIL, flashing, on-device signature interoperability, reboot/retire
persistence, keygenMs measurements, and idle heap ≥40,000 / heapBig ≥28,000
checks remain unexecuted; their USB tests are added. `/tmp/hilvenv` lacks
cryptography: install it with `/tmp/hilvenv/bin/python -m pip install cryptography`
before HIL (not installed during this offline task). No app, HAL, archived
implementation, leaderboard or share-card work is included.
## Phase 7 notes

2026-09-09 — Mac companion surfaces implemented in `app/`. No changes to
`archived/`, `firmware/`, other `plan/` documents, or `.github/`.

### Implementation map

- `Boop/Views/Creature/CreatureView.swift`: pure `CreaturePose(from:)`, six-state
  Canvas/TimelineView face, effort, cheer sizes, urgent-state overlay suppression,
  first-wake eye sequence, cosmetics, session dots, focus mark, deterministic
  frozen poses and an 18 pt menu-bar face. Anatomy and animation vocabulary were
  checked against `firmware/esp32/firmware/face.h` (read only).
- `Boop/Views/PopoverView.swift` and `CompanionViews.swift`: large creature, state
  pill, approval card with stakes, per-session completion/moment, collectable gift,
  bubble, recap tally, connection/growth/focus footer, profile page and windows.
- Existing `Views/Onboarding/` reshaped to welcome → agents → device → name →
  first cheer. Hook diagnostics distinguish real agent traffic from installation.
  Name is locked on confirmation and its saved snapshot is sent to the device.
- `CompanionSettings.swift`, `SettingsView.swift`, `AppDelegate.swift`: settings
  window and recap menu; existing installer/repair and BLE/firmware controls are
  retained. Added stepped volume, daily focus hours, language, voice, quick text,
  local leaderboard preference and retirement confirmation.
- `Core/BuddyEngine.swift`, `Store/Store.swift`, `DefaultsKey.swift`,
  `Voice/Recap.swift`, `TeachCatalog.swift`, `Resources/teach.json`: persistent
  seen/muted tools, retirement/wipe and in-flight work guards, quick notification
  fallback, focus scheduling and recap tally. The only reducer addition is the
  `onboardingCheer` event: a demonstration hop/gift without fake work or XP.
- Desktop/device outputs and NotificationManager carry the new icon, volume,
  quick/retire commands and opted-in needs-you notification behavior. BuddyTheme
  has adaptive cream/charcoal colors; new copy is keyed in BuddyCopy in en/ko.
- `CompanionTests.swift`, `SnapshotHarnessTests.swift`, `CompanionScenes.swift`,
  `SnapshotRenderer.swift`, generated runner and Package.swift cover the new
  behavior and include the teach resource without a new dependency.

### Verification

Baseline generated runner: **408 tests**. The requested initial `swift build
--product Boop` exited **1** before source compilation because the sandbox denied
`~/.cache/clang` writes. A clean baseline test pass was not obtained. The available
permission profile forbids escalation; writable temporary caches worked instead.

Final commands run from `app/`, with:

```sh
export CLANG_MODULE_CACHE_PATH=/tmp/boop-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boop-swift-cache
export BOOP_SKIP_SNAPSHOTS=1
swift build --disable-sandbox --product Boop
swift build --disable-sandbox --product BoopSignal
python3 tools/gen-test-runner.py
swift run --disable-sandbox -j 2 BoopTests
```

All four commands exited **0**. Final result: **406 passed, 11 skipped, 0 failures
of 417 tests** (+9). `git diff --check` also exited **0**. Logs are in
`/tmp/boop-final-build.log`, `/tmp/boop-final-signal.log`, and
`/tmp/boop-final-tests.log` (local, not committed).

Seven skips are snapshot tests; four are existing real-localhost HTTP tests that
skip when the OS sandbox prohibits sockets. An existing `.enable` marker was
left intact. The first GUI-enabled attempt was interrupted (exit 130); the added
`BOOP_SKIP_SNAPSHOTS=1` override allows sandbox verification without renaming that
marker. Outside the sandbox, unset the override and use the existing marker to
run the snapshot harness. Frozen onboarding does not install hooks or start BLE
scanning, and snapshot engines use the scratch defaults suite.

### Data-driven scene list

`CompanionScene.all` contains 44 fixtures:

- All six states × hop/cheer/dance (18).
- Working light/hard/grinding (3).
- Needs-you fine/checkIt/careful (3).
- Uh-oh error/stuck/hungry, with their bubbles (3).
- Greet levels 1/2/3 and boop (4).
- Skins default/sky/mint/ember/midnight; accessories none/sprout/scarf/crown;
  silhouettes default/round/tall (12).
- Idle gift with story line (1).

Each fixture renders both a creature and real popover in light and dark (176
PNGs). Additional paired-appearance scenes: recap (2), profile empty/three lines
(4), all five onboarding steps (10), and 15 settings scenes (30): sounds, focus,
language, voice, quick, leaderboard, profile, retire, general, buddy, agents,
displays, about, companion controls together, and all sections together.
**222 new PNG scenes**, alongside the existing snapshot collection. The harness
checks that every creature/popover catalog output exists.

### UX decisions and remaining verification

- Quick command uses a quiet notification, never a shell subprocess. This tree
  has no documented adapter for safely injecting text into the focused running
  agent session. Settings explicitly describes the fallback. Notification
  delivery still depends on macOS authorization.
- Focus is scheduled in local whole hours, every day; overnight ranges work and
  equal start/end means all day. Manual focus lasts until a schedule boundary.
- Names are trimmed and constrained to the existing wire's 23-byte UTF-8 limit
  while typing so the Mac and device keep the same permanent name.
- The first-cheer demo does not create a session, completion, ledger row or XP.
  It is skipped by the engine if real work has already completed.
- Settings and profile use reusable native windows. Session rows scroll after
  three rows. The onboarding window is 660 pt high to give the creature room.
- Retirement waits for current persistence/voice work, prevents older extraction
  and reflection results from restoring the previous owner, wipes the local
  owner store and sends the retire command over the existing BLE transport.
  This command is not an acknowledgment of hardware delivery.
- New face art, motion, layout and contrast still require the requested outside-
  sandbox PNG review and a real onboarding/device walkthrough. No screenshot,
  Bluetooth delivery, live hook/doctor, notification presentation or hardware
  fidelity pass is claimed here.

## Phase 8 app notes

Implemented 2026-09-09; `archived/`, `firmware/`, other `plan/` files and
`.github/` are unchanged. No commit or push.

### Implementation

- `app/Boop/Leaderboard/DeviceSigning.swift`, `DeviceProtocol.swift`,
  `ESP32Output.swift`, and `BuddyEngine.swift`: query identity on connect;
  validate P-256 SEC1 keys and 16-hex unit IDs; pin identity; send a random
  16-hex nonce with the local day and lifetime XP; match the pending request
  and locally verify DER ECDSA before persistence. Strict integer parsing
  rejects booleans, floats (including integral floats), and malformed fields.
- Store schema 4 adds `unit(unit,pub,alg,first_seen)` and
  `ledger_signatures(day,xp,nonce,sig,unit)`. One signature per local day,
  unique nonces per unit, identity retained across restarts, cleared at retire.
  Retirement invalidates in-flight work and waits for signing/sync to finish.
- `LeaderboardClient.swift` contains a deliberately narrow submission DTO.
  URL/opt-in/friends settings, daily SQLite upload reservation, signature
  cursor and rank fetching are wired into the engine. Only the new
  `leaderboardUpdated` event changes the reducer. Rank all/month/friends is
  available in the popover footer sheet; software-only users keep growth but
  cannot submit a score. The coming-soon label is removed in both languages.
- `ShareCard.swift` renders the current creature/cosmetics, name, level,
  streak and an authored share line with ImageRenderer. English and Korean
  each have eight lines per earnest/wry/cheeky register. Cream-only card art
  uses darker facial features, an upright frozen pose, and omits session
  indicators. Menu and popover actions save a unique PNG in Downloads, copy
  PNG data to the pasteboard, and reveal the saved file. Snapshot scenes
  cover both languages and appearances, plus the shipping ImageRenderer.
- New `leaderboard/` SwiftPM package: Hummingbird 2, system SQLite,
  transactional signature verification/duplicate rejection, latest totals,
  three rank views, health endpoint and deployment README. Hummingbird is
  the only package dependency; CryptoKit verifies on macOS and system
  OpenSSL verifies on Linux. No request logging middleware or IP columns.
- Tests cover tampering, invalid identity/algorithm, strict wire decoding,
  persistence/replay/retire, fixture gating, exact HTTP body keys, opt-out,
  empty endpoint, concurrent upload reservations, restart limits, friends
  query isolation, and extractor/profile privacy. Service tests cover
  verification/rejection, duplicates and rollback, rank ordering/month/
  friends, and actual Hummingbird routes without sockets.
- `app/tools/e2e/lib.sh` adds `leaderboard_check`, called by the master smoke
  runner when the service builds. It starts an isolated service on a random
  port, injects the gated test signature, asserts exact body keys and rank 1
  in all three views, restores URL/opt-in, and stops its service. It requires
  a fresh named headless software buddy launched with `BOOP_TEST_SIGNER=1`;
  it does not replace a recorded hardware identity or reset an owner's data.

### Verification evidence

The first default build exited 1 before project compilation because the
sandbox denied user module-cache writes. Builds succeeded with
`CLANG_MODULE_CACHE_PATH=/tmp/boop-clang`,
`SWIFTPM_MODULECACHE_OVERRIDE=/tmp/boop-swift`, and SwiftPM's
`--disable-sandbox` flag (the outer workspace sandbox remained in effect).
The new service reused the app's already resolved Hummingbird checkouts;
no dependency download was claimed in this network-restricted environment.

| Command | Exit | Result |
| --- | --- | --- |
| `cd app; swift build --disable-sandbox --product Boop` | 0 | Swift 6 build |
| `cd app; swift build --disable-sandbox --product BoopSignal` | 0 | Swift 6 build |
| `cd app; python3 tools/gen-test-runner.py` | 0 | 428 tests generated |
| `cd app; swift run --disable-sandbox BoopTests` | 0 | 417 passed, 11 skipped, 0 failures |
| `cd leaderboard; swift build --disable-sandbox` | 0 | Service and local test runner built |
| `cd leaderboard; swift test --disable-sandbox` | 1 | XCTest unavailable; no test target on this CLT host |
| `cd leaderboard; swift run --disable-sandbox LeaderboardTests` | 0 | 4 passed, 0 failures using the repo's XCTest shim |
| `app/.build/debug/Boop --render-snapshots /tmp/phase8-snapshots-reviewed` | 0 | Both languages/appearances rendered; image review completed |
| PNG IHDR checks | 0 | Four ImageRenderer exports are exactly 1200×630 |
| OpenSSL C fallback compile/run on macOS | 0 | Identity, valid signature, tampered message and invalid key checked |
| `bash -n app/tools/e2e/lib.sh app/tools/e2e-smoke.sh` | 0 | Shell syntax valid |
| `git diff --check` | 0 | No whitespace errors |

App skips: four existing real-socket tests (sandbox prohibits localhost
sockets) and seven opt-in snapshot harness tests (disabled by default).
The standalone renderer was run separately; reviewed card exports are in
`/tmp/phase8-snapshots-reviewed/share-image-renderer-{en,ko}-{light,dark}.png`.
Final command logs use `/tmp/phase8-verify-*`. Native `swift test` is not
claimed as passing: the service uses a real XCTest target on full Xcode or
Linux and an explicitly invoked local shim runner on Command Line Tools.

Unexecuted: socket e2e/master smoke, Bluetooth unit/sign round trip, hardware
key persistence, native Linux Swift build, and the interactive Downloads/
pasteboard action. No hook/doctor or hardware pass is claimed.

### Contract decisions beyond the older prose

1. The explicit wire spec overrides architecture shorthand: unit is eight
   SHA-256 bytes (16 lowercase hex characters); signed ASCII is
   `unit|day|xp|nonce`. The submit envelope has **exactly seven keys**:
   `buddyName`, `silhouette`, `xpTotal`, `signatures`, `unit`, `pub`, `alg`.
   Every signature has exactly `day`, `xp`, `nonce`, `sig`. The older “four
   fields” language describes payload categories before identity metadata.
2. Signing occurs at the first connected opportunity each local day (with
   minute retries on transport failure), and on headless `/state/sign`.
   Scores use the latest *signed* total, never newer unsigned XP. Opt-out
   stops leaderboard networking but does not stop local device signing.
3. At most one POST attempt per local day, including failures, is reserved
   atomically in SQLite. Unsent signatures retry the next day in batches of
   up to 400. An accepted POST whose reply was lost may later receive a
   replay conflict: this minimal protocol intentionally rejects duplicates
   and has no reconciliation endpoint.
4. Month means latest total minus the last signed total before the current
   UTC month, with baseline zero for a new unit. Local day labels allow one
   day of UTC skew. Totals cannot decrease; supplied days must advance.
   Ties use unit ID ascending; views return the first 100 entries plus the
   requesting unit's rank across the full view.
5. Friends codes are the uppercase first six unit characters, capped at 100
   local friends. Query key `friends` carries a JSON array. It is absent
   from submissions and never stored by the service. Prefix collisions
   include all matching units; codes are discovery aids, not authentication.
6. The service has no manufacturer allowlist: a valid per-key signature
   demonstrates possession of that key, not independently measured work.
   TestDeviceSigner construction in production flow is gated by headless
   configuration and `BOOP_TEST_SIGNER=1`. The Linux crypto adapter uses
   system OpenSSL to honor the Hummingbird-only package dependency rule.


### Native Mac UI pass (2026-09-09)

On a CommandLineTools-only Mac, enable the snapshot harness and run the
SwiftPM test executable from `app/`:

```sh
swift build
mkdir -p /tmp/buddy-snapshots
touch /tmp/buddy-snapshots/.enable
python3 tools/gen-test-runner.py
swift run BoopTests
```

If user-level caches are sandboxed, set `CLANG_MODULE_CACHE_PATH` and
`SWIFTPM_MODULECACHE_OVERRIDE` to writable `/tmp` directories and pass
`--disable-sandbox --cache-path /tmp/boop-ui-cache` to SwiftPM. This only
fixes build caches; it does not grant localhost socket permission. The
local UI pass produced 426 passed and 4 skipped (HTTP/socket tests).
Release verification still requires a run with zero skips.

Review the light/dark popover, profile, onboarding, and settings PNGs in
`/tmp/buddy-snapshots`. Settings windows are 760 pt wide and popovers 360 pt.
Legacy settings scene names remain available alongside the new Device and
Advanced scenes; `expectedRenderCount` includes both. Confirm all five
settings destinations and their controls manually on a clean account.

The offscreen renderer on this macOS host omits the native sidebar's row
labels even though the five destination forms render. The navigation
snapshot is therefore not a visual acceptance result; inspect the sidebar
and selection in the live Settings window. The renderer waits for native
layout and uses active control appearance so the approval accent is visible.


### Device RGB332 UI correction (2026-09-09)

`face.h` and `main.cpp` remove the glow and bubble pill, retain the
900 ms eye sweep, and add a single skin-tint field flash (300 ms toward
tint, 300 ms back). Sleep ink is dimmer; secondary text and the stats
track use `animRGB(146,146,146)`. Blush, hop ripple, and battery mark use
explicit visible colors. Remaining blends are visible ink transitions,
eye highlights, or whole-field washes/flashes. Drawing adds no wall clock
or frame-history dependency; the flash uses `nowMs() - ritualAt`.

Validation: `tools/pio_ws.sh run -e ws-amoled164` from `firmware/esp32`
exited 1 at the home-directory PlatformIO lock under the sandbox. The
same command with `PLATFORMIO_CORE_DIR=/private/tmp/boop-ui-pio` and
`PLATFORMIO_PACKAGES_DIR=/private/tmp/boop-ui-pio/packages-pioarduino`
passed (exit 0). Dependency refresh emitted offline warnings but the
installed tools compiled and produced both firmware binaries. Static
comparison confirms all committed STATE keys remain; the uncommitted
`glow` addition is removed. `git diff --check` passed.

Hardware follow-up: inspect bare eyes and two-line bubbles on RGB332;
check hint/count/track grey, 2 px armed ring and 4 px hold arc; freeze
level-up at 0/150/300/450/600/900 ms and compare repeated frames. Run the
existing USB HIL suite for card arming, feedback, priority, and decision
commands. No flash or USB HIL was run for this pass.


### The device has one writer (2026-09-09)

Every device capture — contact sheet, goldens, HIL, soak — requires the Boop
app to be quit. The app pushes its own frames over BLE, so with it connected
a real card or session-dot update lands between the test's frame and the
screenshot, and the result is silently wrong rather than failing. A set of
goldens was recorded this way before anyone noticed. `tools/shots.py` and
`tools/soak.py` now exit with an explanation when `state.connected` is true,
and the HIL fixtures skip. Re-record goldens only from a run where that
guard passed.

### Motion review (2026-09-09)

Animations are judged from strips, not single frames:
`firmware/esp32/tools/motion_strip.py <moment>` freezes the virtual clock
at several offsets after a moment starts and stitches the screenshots
(`/tmp/boop-motion/<moment>.png`). A rendering change to any moment in
`UX-DEVICE.md` §20 ships with its strip in the pull request, and the
goldens are re-recorded only after the strips have been looked at.

## Test entry point, 2026-09-09

Run `make test` from the repository root. `app/tools/test.py` reads SwiftPM
package metadata to use the exact target type selected by `Package.swift`.
For an executable test target it regenerates and runs `BoopTests`; for a test
target it runs `swift test`. There is no compile-only success path. This
removes duplicated XCTest detection from Make without changing the tests.

`GrowthCoordinatorTests` controls signature and HTTP response timing to check
that disconnect and retirement reject late work, opt-out rejects stale ranks,
failed submissions release their reservation and respect backoff, forced retry
works, and three queued callers retain their requested views. A fixture output
implements the signing capability without BLE to exercise engine routing. A
store exposing only `GrowthStore` verifies enrollment/disconnect handling without
coupling tests to the engine's larger store interface. These run under `make test`.

`TransientVoiceTests` holds generation open through replacement, cancellation,
language/runtime changes, stop, and gift collection; late replies must not
replace current text, and the two lanes must remain independent.
`ESP32PreferencesTests` uses separate preferences suites to check saved UUID
lookup, invalid UUID handling, unpair isolation, and live name/volume/mute
changes in the output's actual frame encoder. These checks do not start a radio.

`BuddyStateEncodingTests` compares initial, fully populated, six-state, and
overlay samples against `app/Tests/Fixtures/state/diagnostic-before-projections.json`.
That fixture was captured from the pre-migration synthesized encoder; the full
sample contains all 36 diagnostic fields. A separate test mutates the creature
without a reducer pass to prove the legacy properties cannot drift. Desktop
snapshot images are compared against a pre-migration capture for this pass.

The 2026-09-09 final comparison passed diagnostic JSON parity and 445 tests with
zero skips. Snapshot evidence is in
`plan/evidence/architecture-refactor/snapshot-comparison.json`: 146 images are
byte-identical; the remaining image was visually reviewed and differs only by
one RGB level at 155 edge pixels. This is not a claim of byte equality for that
image or of a newly verified BLE transport run.


## CI invocation policy (2026-09-10)

The `CI` GitHub Actions workflow is manual-only (`workflow_dispatch`) at the
owner's request to stop failure emails on every push. Pushes and pull requests
no longer launch it. Existing jobs remain available via Actions → CI → Run
workflow; their previously reported failures have not been diagnosed or fixed
by this trigger change. Local verification commands remain available. Release
workflows retain their existing triggers.


## XP-independent availability checks (2026-09-10)

Store regression coverage checks the full catalog before any growth calculation,
equipping former high-level cosmetics at zero XP, rejection of unknown IDs,
persistence on reopen and unchanged XP calculations. Appearance availability
must not depend on earned XP. No firmware or wire change is involved; webcam
verification is not required or activated by this change.

Validation: full `make test` passed 445 tests with zero skips after this change.

## Control center verification (2026-09-10)

The snapshot harness renders Overview, Activity and Settings at 760×620 alongside
existing approval and onboarding cases. Store coverage checks capped XP awards
in the daily/source history and correct within-level progress. Desktop output
coverage asserts completion no longer duplicates the device's celebration sound
while approval notifications remain. Live window/navigation and physical BLE
behavior require a user-launched app; agent checks use offscreen snapshots and
the test suite and do not start the graphical app.

Validation: full `make test` passed **448 tests, zero skipped**. Offscreen
Overview, Activity, Settings, Appearance, approval and welcome snapshots were
visually reviewed for readable layout and removal of the everyday pet face.
The capped-award history test exercises the `EngineStore` protocol boundary,
and desktop tests cover no completion auto-open or idle auto-close. Live window
interaction and BLE were not exercised in this pass; the user must launch Boop
for that iteration. No camera was used.

## Parallel feature verification (2026-09-10)

Use one worktree per feature and `make e2e` for an isolated headless instance.
Instances retain scratch state and stay running for inspection; explicitly stop
with `app/tools/headless.sh --stop`. Normal hooks remain on the everyday app.
For hardware, quit the GUI, then use `make hil`, `make hil-ble`, or the setup /
scenario / restore wrapper in `tools/dev/README.md`. Keep the GUI closed during
the reservation. Firmware scripts must verify board and firmware identity.
Review the recorded setup, scenario and restoration outcomes; a restoration
failure requires recovery. Tooling checks: `python3 -m unittest discover -s
tools/dev/tests -v`. Physical validation remains separate and requires a device;
these tooling tests never touch hardware. The live-hook doctor is exclusive.

## Landing deployment checks (2026-09-10)

From `landing/`, use Node 24 (`nvm install` reads `.nvmrc`), then run `npm ci`,
`npm run lint`, `npm test`, and `npm run build`. The build includes TypeScript
and static-route validation. No database credentials are needed for these
checks. Confirm Vercel's project root is `landing`, its Node version is 24.x,
and deployment skipping for unaffected roots is enabled in project settings.
After an authorized push, verify the matching commit reaches Ready / Current
in Production. A successful build does not verify live database writes or
email delivery; those require a separately authorized signup test.

## Hook integration correction (2026-09-10)

Regression checks execute the generated shell script with a scratch config and
HTTP stub: a global approval switch alone cannot intercept Codex, explicit
Codex opt-in can route requests, Claude routing remains available, and ordinary
Codex activity still forwards. Payload tests cover aliases, call IDs, error
class and approval descriptions separate from destructive-command stakes.
Live Codex doctor against the owner's running app: 8 passed, 0 failed, 0 warnings;
live confirmation passed. Installed script was v7, before these changes.
Claude configuration inspected; live Claude confirmation not performed here.
Cursor has no user hooks file on this machine; live Cursor verification remains
required. Test results and install status are recorded in HOOK-REVIEW.md.

Validation: `make test` passed 452 tests with zero skips; advanced-settings
snapshot rendered and visually reviewed. Full log: `/tmp/boop-hook-review-tests.log`.
Final `make build` passed for Boop and BoopSignal outside the cache-restricted sandbox.
