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
