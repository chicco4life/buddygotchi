# Implementation Plan

Status: first draft, 2026-09-08. Turns `VISION.md`, `UX-DEVICE.md`,
`ARCHITECTURE.md`, and `VERIFICATION.md` into phases that can be built and
verified one at a time. Each phase ends with a checklist that an agent can
run and a human can accept from the evidence alone.

---

## 0. How to read and run this plan

- **One phase, one branch, one pull request** (or a small stack of PRs
  that merge together). A phase is done when its exit checklist is green
  and the evidence is attached.
- **Nothing breaks between phases.** After every phase the app builds, the
  full test suite passes, the current firmware still pairs and renders, and
  the doctor passes. Phases that change the wire keep a shim for the old
  contract until the firmware phase lands.
- **Verification first.** Phase 0 exists so every later phase can be
  verified by an agent without a human in the loop for anything but
  launching the app and plugging in the device.
- **Where code lives.** The previous implementation is under `archived/`
  and keeps building. New work is built outside `archived/`, copying forward
  the pieces `ARCHITECTURE.md` §10 keeps (hook script and installer, server
  routes, engine and reducer, BLE transport, OTA, firmware HAL and HIL).
  Commands in this plan that reference `archived/…` are the current tooling,
  used until the phase that replaces it lands.
- **Sizes** are relative: S is a day or two of agent work, M a week, L two
  or more. They are for ordering, not scheduling.
- **Human steps** are called out per phase. They include launching the Boop app from a terminal, plugging in or pairing
  the device, and positioning it for optional webcam review with camera permission.

Dependency order:

```
 0 verification ─► 1 six-state core ─► 2 wire v2 + firmware core ─► 6 device experience
                          │                                            ▲
                          ├─► 3 extractor + moments ─► 4 store ─► 5 voice ┘
                          │                               │
                          └─► 7 desktop experience ◄──────┘
                                        │
                                        ▼
                               8 growth loop ─► 9 hardening + release
```

Phases 3 and 7 can start in parallel once 1 is merged. Phase 6 needs 2 and
5. Phase 8 needs 4 and 6.

---

## Phase 0: Verification foundation

**Goal.** An agent can run every non-hardware test on its own, and every
hardware test with a device plugged in, and can prove what it saw.

**Size.** M.

**Build.**

1. `GET /diag/recent?n=` behind the token, returning the engine's diagnostic
   ring buffer as JSON.
2. `GET /state` behind the token and a debug flag, returning the full
   `BuddyState`.
3. Headless app mode: `swift run Boop --headless` starts server, engine, and
   outputs with Bluetooth and the status item disabled, no TCC prompt.
   Desktop output renders offscreen so snapshots use the real path.
4. Doctor confirm step reads `/diag/recent` for an entry from the harness's
   source when available, version delta as fallback.
5. Snapshot harness uses a scratch defaults suite.
6. Replace the stale `.cursor/hooks.json` with the installer's output.
7. Pin the Xcode version in CI; add the lint step.
8. `tools/record-hooks.sh`: a wrapper that tees a hook payload to a
   fixture file with paths and text redacted.

**Exit checklist.**

- [ ] `swift test` green in CI on the pinned toolchain, twice in a row (no
      defaults poisoning). CI not yet run on the new tree.
- [x] From a fresh shell: `app/tools/headless.sh`, then
      `app/tools/e2e-smoke.sh` green (108 assertions, run from inside a live
      Claude Code harness), `/diag/recent` shows every posted event by
      source, then `--stop`. No human step. (2026-09-08)
- [~] `skills/doctor/doctor.sh` passes the static checks and the live confirm
      against the headless app from Claude Code (2026-09-08). Codex and
      Cursor runs still owed.
- [ ] `app/tools/record-hooks.sh` produces a redacted fixture for one real
      Claude Code session. Script written and syntax-checked; only hand-built
      SessionStart fixtures are committed so far.
- [x] Stale Cursor hooks file removed (2026-09-08).
- [x] Headless launch does not touch Bluetooth: verified by an agent-launched
      run on the developer's Mac, no TCC prompt, no abort. (2026-09-08)

**Human steps.** None, except a one-time confirmation that the headless app
really does not prompt for Bluetooth on their machine.

**Risk.** Headless mode may need a real `NSApplication` for some SwiftUI
paths; fall back to a minimal app delegate with the status item hidden.

---

## Phase 1: Six-state core

**Goal.** The reducer speaks the new vocabulary and the app renders it,
while the current firmware keeps working through a shim.

**Size.** M.

**Build.**

1. New `BuddyState`: state (asleep, idle, working, needsYou, done, uhoh),
   effort, cheer size, uhoh kind, overlay and greet level, session dots and
   alert index, card, bubble, gift and gift line, focus, snapshot.
2. Reducer: sessions, collapse by priority, effort accumulators, cheer
   sizing with a single thresholds table, nudge ladder timing with
   dismissal halving and auto-snooze, focus gating, stuck detection.
3. Events: turnStarted, toolCalled, toolResulted, turnEnded, needsYou with
   gloss and stakes, focusToggled, collect. Old events map onto these.
4. A **shim** in the device output mapping the new state to the current
   `RenderState` (pet strings, celebrate flag) so today's firmware still
   renders something sensible.
5. Desktop output: status item and popover show the six states and cheer
   sizes with placeholder art. No new screens yet.

**Exit checklist.**

- [ ] `ReducerTests` cover every state transition, the collapse across
      three sessions, each cheer size threshold, each nudge rung, dismissal
      halving, auto-snooze, focus, stuck.
- [ ] `EngineIntegrationTests` prove each new event reaches `BuddyState`.
- [~] Popover snapshots for asleep, working, needsYou, done (hop), and uhoh
      (error) reviewed and filed under `plan/evidence/phase-1/` (2026-09-08).
      Scenes for cheer/dance and stuck/hungry still to add to the harness.
- [x] e2e suite (headless) asserts the six states through `/state` for
      each agent script: 108/108 with Phase 0 landed (2026-09-08).
- [x] Current firmware, flashed as-is, renders busy, attention, celebrate,
      and error through the shim vocabulary: `plan/evidence/phase-1/` (2026-09-08).

**Human steps.** Plug in the device for the shim check.

**Risk.** The reducer rewrite is the largest pure-logic change; keep the
old reducer tests running against the mapping until the new suite is
complete, then delete them.

---

## Phase 2: Wire v2 and firmware core

**Goal.** The device renders the six states from the new contract, on the
desk posture, with the card, bubble, gift, and sounds. The old renderer,
menu, glance card, fireflies, and mood engine are gone.

**Size.** L.

**Build.**

1. `RenderState v2` encoder with a version field, byte caps on character
   boundaries, and the frame cap. Remove the shim.
2. Device-to-host commands: decision, collect, boop with hold, focus,
   battery, status with board id.
3. `buddyctl frame --json` and `buddyctl set --t <ms>` for a frozen clock.
4. Firmware: parse and validate v2, device model, renderer by screen
   priority, face parts with composable expressions, field, sparks, one
   card, one bubble, gift orb, seven sound motifs with manners, dim ladder
   with a never-off sleep frame, card arm delay and wake-press guard,
   shutdown hold ladder.
5. `tools/shots.sh` contact sheet and golden screenshot comparison in HIL.
6. HIL suite rewritten for the new vocabulary; hardening tests kept.

**Exit checklist.**

- [x] Encoder tests for every capped field at the byte boundary, including
      a Korean bubble. (2026-09-08)
- [x] Compatibility: unknown keys ignored, legacy frames rejected with the
      last good model kept (`badFrames` counts them). HIL-covered. (2026-09-08)
- [x] USB HIL green: 31 device tests + 4 hardening tests, three consecutive
      clean runs with the panic counter flat (2026-09-08). Watchdog recovery
      verified once by observation (task_wdt reset, USB re-enumerated); the
      hang test is run by hand because a stranded USB port needs a physical
      reset. Panics seen on a device already in post-hang recovery were not
      reproducible on a clean device: tracked for Phase 9 hardening. each of the six states, three effort levels, three
      cheer sizes, card at each stakes level, decision round trip with
      ack-driven "yes!", gift collect, bubble timing, dim ladder never
      reaching off, shutdown ladder stages, heap floors.
- [x] Contact sheet cells reviewed against `UX-DEVICE.md` and filed under
      `plan/evidence/phase-2/` (2026-09-08).
- [x] Goldens checked in under `firmware/esp32/tests/golden/ws-amoled164/`;
      21/21 across two independent captures once animation phases were
      anchored to state entry and `clock settle` landed (2026-09-08).
- [ ] Sound: each motif recorded from the device and tellable apart. Blocked:
      the Waveshare board has no speaker; the table and manners exist and are
      reported in the state reply.
- [ ] `make hil-ble`: prompt round trip over the production transport. Needs
      the Mac paired; not run by the agent.

**Human steps.** Plug in and pair the device; listen to the motifs once.

**Risk.** Highest of the plan. Mitigate by landing the encoder and
`buddyctl frame` first so firmware work is driven by frames from day one,
and by keeping the HAL untouched.

---

## Phase 3: Extractor and moments

**Goal.** The app sees the transcript stream, holds it in memory per
session, and turns it into events and facts. The tenth try produces a
dance with the right story facts.

**Size.** L.

**Build.**

1. Hook script v5: forward full tool input, exit status or error class,
   first and last 1 KB of output, prompt text on turn start, closing
   message on turn end, 16 KB body cap. Installer bumps and repairs.
2. `RawHookPayload` per-agent parsers in the server; handoff to the
   extractor.
3. Session window: bounded by entries and bytes, eviction, drop on session
   end and app quit, never serialized. Compact per-goal tally kept
   alongside so eviction never loses a count.
4. Readers: lifecycle, goals with the runner table and outcome reading,
   stakes and gloss, effort, theme with tone and topic reduction, closing
   line summary source.
5. Moments in the reducer: hardWonPass, redStreakEnded, backAfterAbsence,
   sameFileAgain, lateNight, nthRateLimit, firstEver. Cheer size becomes a
   function of the moment.
6. Fixture corpus: `archived/app/Tests/Fixtures/hooks/<agent>/<version>/` recorded
   with the Phase 0 tool, one stream per scenario including a ten-attempt
   test run for each agent.
7. `adapterDegraded` when a reader cannot find its fields.

**Exit checklist.**

- [ ] Fixture replay tests for each agent: expected events, facts, stakes,
      glosses, moments.
- [ ] Window tests: eviction keeps the goal tally; session end drops the
      window; nothing raw is ever written (a test that greps the app's
      writable directories after a replay).
- [ ] Stakes classifier fixtures: destructive shell, deletes outside the
      project, network, credentials, installs are careful; control
      characters force careful.
- [ ] e2e tenth-try scenario per agent (headless): `/state` shows
      grinding effort, then cheer size dance with the moment facts.
- [ ] Doctor still passes from each harness with hook script v5.
- [ ] Memory ceiling test: a synthetic 10,000-entry session stays under
      the window cap.

**Human steps.** Run one real session per agent while recording fixtures.

**Risk.** Agent payloads differ by version; the corpus is the defense.
Outcome reading will have gaps; unknown is allowed and must never become
a guess.

---

## Phase 4: Store

**Goal.** Facts, profile, traits, and the growth ledger persist in one
SQLite database; XP, level, and streak are real; the profile is visible
and clearable.

**Size.** M.

**Build.**

1. SQLite store with the five tables and a migration mechanism.
2. Facts written from extractor output and moments; 30-day pruning.
3. Ledger with the public XP formula applied at read time; level curve;
   streak with one banked rest day per week; cosmetics inventory.
4. Traits with capped daily drift from the defined inputs; hidden bond.
5. Profile lines with source and confidence; clear line and clear all;
   clearing keeps name, level, bond.
6. Nightly job skeleton: rules-only profile candidates (rituals from
   facts), no model yet.
7. `PetMemory` migrated in; old persistence removed.
8. Growth snapshot in `BuddyState` and in the frame's `snap`.

**Exit checklist.**

- [ ] Ledger tests: formula, level thresholds, streak with rest days,
      approvals never award, a formula change re-reads history correctly.
- [ ] Migration test from a real pre-Phase-4 `PetMemory` file.
- [ ] Profile tests: add, clear one, clear all, what survives.
- [ ] Trait drift tests hit the daily caps.
- [ ] e2e: a replayed day of fixtures produces the expected XP total and
      a fact count that prunes at 30 days.
- [ ] Device shows the snapshot in travel stats (uses Phase 2 firmware).

**Human steps.** None.

**Risk.** Formula tuning is product work; the plan only requires the
mechanism and the public explanation to match.

---

## Phase 5: Voice

**Goal.** The buddy talks. A local model writes lines within budget,
authored banks are the floor, the device gets story lines, and the nightly
job uses the model.

**Size.** L.

**Build.**

1. Runtime abstraction with one implementation chosen by a latency bench
   across the Macs the audience owns; model download and integrity check
   in the app.
2. Prompt assembly from moment, profile lines, traits, agent, time,
   language. Post-filter for owner-directed negative lines. Byte cap.
3. Authored banks per language and per moment, English and Korean,
   with a selection that avoids repeats.
4. Budget: one second for a device line, fallback on miss, model result
   discarded.
5. Nightly reflection with the model: candidate profile lines and trait
   deltas, caps applied, closing lines dropped afterward.
6. Wire: bubble and gift line populated from voice.

**Exit checklist.**

- [ ] Latency bench results recorded for at least three Mac generations;
      the chosen runtime meets budget on the slowest.
- [ ] Golden tests on the authored banks in both languages.
- [ ] Post-filter property tests: no line passes that addresses the owner
      negatively.
- [ ] Fallback-on-timeout test with a stubbed slow model.
- [ ] Reflection test: a replayed day yields at most five lines and
      capped deltas; closing lines are gone afterward.
- [ ] Device HIL: a tenth-try frame shows a Korean story line legibly.
- [ ] Two testers describe their buddy's personality unprompted after a
      week (the sprint plan's bar, kept).

**Human steps.** Run the bench on their own machines; a week of real use.

**Risk.** Model quality is the vision's biggest bet. The authored banks
must be good enough to ship alone; the model is an upgrade, not a
dependency.

---

## Phase 6: Device experience

**Goal.** Everything in `UX-DEVICE.md` Part I works on hardware: postures,
travel mode, rituals, cosmetics rendering, sleep that never powers down.

**Size.** L.

**Build.**

1. Posture detection from the IMU; desk, perch, and travel animation sets.
2. Travel mode: link-lost timing, stats cards from NVS snapshot, boop,
   pet, shake, flip, pick-up.
3. Rituals: first wake with the Bluetooth mark and grey-until-first-signal,
   greet by gap, level up, streak milestone, retire fade.
4. Sleep frame at lowest brightness all night; measured battery draw.
5. Cosmetics: skin and field tint, accessories, silhouettes within the eye
   anchor.
6. `buddyctl inject imu` for posture and motion in HIL.
7. Multi-session behavior: dots, dot alert, folded cheers, oldest-first
   cards with count.

**Exit checklist.**

- [ ] Contact sheet per posture, reviewed.
- [ ] HIL: posture switching without flicker, travel entry after link
      loss, stats cards content and timing, each motion reaction, each
      ritual, level-up reveal, cosmetics render without covering eyes.
- [ ] Overnight sleep on battery survives to morning (a real night on the
      bench, numbers logged).
- [ ] Multi-session HIL: three sessions, three prompts oldest first, two
      near-simultaneous completions fold into one cheer.
- [ ] First-wake flag: a factory-reset device plays the ritual once.

**Device UI correction (2026-09-09).** Removed the radial glow and bubble
fill for RGB332. Skin and sleep brightness live in eye ink; level-up uses
the eye sweep and a 300 ms rise / 300 ms return whole-field flash. Hold
strokes are full ink (2 px idle, 4 px filling); hints, queue count, and
stats track use explicit grey. S3 build passed with writable PlatformIO
cache overrides; hardware visual review and USB HIL remain pending.

**Device motion correction (2026-09-09).** Implemented `UX-DEVICE.md`
§20: removed perch feet, scrolling hearts, hop ripple, rectangular confetti,
dizzy Xs, and cheer spin. Added clock-sampled spring motions, one heart,
six dance dots, gaze-only dangle, and a 200 ms collect shrink that survives
the gift bubble transition. The dance ends at 2500 ms. STATE fields and
interaction decisions remain unchanged. S3 build and static field comparison
passed; hardware visual review and the owner's USB HIL run remain pending.

**Human steps.** Perch the device on a lid; leave it overnight on battery.

**Risk.** Posture detection depends on the mount; keep the explicit
posture override in the frame as the fallback.

---

## Phase 7: Desktop experience

**Goal.** The Mac app is the premium companion the vision demands:
onboarding, the creature, the card, the recap, the profile page, settings.

**Size.** L.

**Build.**

1. Onboarding: first wake mirrored, connect agents with per-surface
   detection and a "heard from" moment, name, first cheer.
2. Menu bar creature and popover with finished art for six states, three
   cheer sizes, effort, dots, gift.
3. Needs-you card with gloss and stakes; approve, deny, focus.
4. End-of-day recap screen and the one-line device recap.
5. "What your buddy knows" page: profile lines, clear line, clear all.
6. Settings: agents, sounds, focus hours, languages, leaderboard opt-in,
   retire.
7. Quick command configuration for the double tap.

**Exit checklist.**

- [ ] Snapshots for every screen and state, reviewed in light and dark.
- [ ] Onboarding e2e in headless mode: fresh defaults to named buddy with
      one cheer, per agent.
- [ ] Recap e2e: a replayed day produces the expected recap.
- [ ] Profile page e2e: clear one line, clear all, level and name intact.
- [ ] Accessibility of text sizes and contrast checked by the snapshot
      review (kept minimal per the vision).
- [ ] Doctor passes after onboarding from each harness.

**UI pass (2026-09-09).** Implemented the revised `UX-APP.md` native
materials, five settings sidebar sections, quiet popover, plain profile
list, and face glow. Existing settings bindings and engine behavior are
preserved. Snapshot scenes retain their names; settings captures now use
the window's 760 pt width. The local command-line runner passed 426 tests;
four HTTP tests skipped because the execution sandbox prohibits localhost
sockets. Clean-account onboarding, live control interactions, and the
unrestricted zero-skip run remain review gates. Native sidebar row labels
are absent from offscreen captures on this host; inspect navigation live.

**Human steps.** Walk the onboarding once on a clean user account.

**Risk.** Art and motion quality; budget review rounds on the snapshots.

---

## Phase 8: Growth loop

**Goal.** XP is signed by the device, share cards render, and the opt-in
leaderboard works against a minimal service.

**Size.** M.

**Build.**

1. Per-unit key provisioning and the daily signature command; ledger
   stores signatures.
2. Share card renderer (local image).
3. Leaderboard client: opt-in, pseudonymous submission of name,
   silhouette, total, signatures. A minimal server with verification and
   three rank views, deployable anywhere.
4. Universally available cosmetics catalog wired to the inventory; XP is a
   progress statistic and unlocks nothing (owner decision, 2026-09-10).

**Exit checklist.**

- [x] Signature tests: a tampered total fails verification; a device-less
      ledger cannot submit.
- [x] e2e against a local stub server: submit, rank, friends code.
- [x] Share card snapshot in both languages.
- [x] Privacy test: the submission body contains exactly the four fields
      plus the three identity fields (unit, pub, alg) the service verifies
      against; `LeaderboardClientTests` asserts the exact key set.
- [x] HIL: sign command round trip and key persistence across reboot.

**Human steps.** None beyond the device.

**Finding (2026-09-09, autonomous run).** The first end-to-end submit
failed because a fresh store has no buddy name and the service requires
one; an unnamed buddy now submits and renders as "Boop". The e2e runs
against a scratch `BOOP_STATE_DIR`, never the owner's `~/.boop` store.

**Risk.** Key provisioning at manufacture is a hardware-process question;
prototype units get keys from the app on first pair, marked as such.

---

## Phase 9: Hardening and release

**Goal.** The release gates in `VERIFICATION.md` §4 pass and a build
ships.

**Size.** M.

**Finding (2026-09-09, autonomous run).** The Waveshare board's native USB
serial does not always re-enumerate after a reset: a 40-cycle reboot soak
stranded the device mid-run (no ping, no flasher connection), as the
watchdog test had twice before. Commanded reboots and watchdog resets
usually recover; roughly one in tens does not. Until a root cause is found
(host-side CDC driver, or the firmware's USB init order), treat every
device test that resets the board as needing a person within reach of the
reset button, and keep the soak out of unattended runs. Candidates to try:
`ARDUINO_USB_MODE` 0 (TinyUSB CDC) instead of 1 (HW CDC/JTAG), a delay
before `Serial.begin`, and a host-side re-open loop that tolerates the
port node vanishing.


**Build.**

1. End-to-end latency scenario over BLE with timestamps at every hop;
   numbers against the budgets.
2. Soak at high cycle counts; heap floors re-baselined for the new
   firmware.
3. Per-agent version matrix: fixtures for the current release of each
   agent; the doctor run from each harness.
4. Packaging, signing, notarization, appcast, firmware manifest.
5. Support paths: help page, reset and retire flows, what to do when a
   harness ships a hook regression.

**Exit checklist.**

- [x] Latency table filled at p90 and every row within budget:
      `plan/evidence/phase-9/latency.md` (hook→card 398 ms, button→decision
      137 ms, state→frame 124 ms at p90; `firmware/esp32/tools/latency.py`).
- [x] Soak and hardening green: 256-cycle soak with heap flat at 195 kB
      minimum, no panics or reboots; hardening suite 5/5 including the reboot
      soak (`plan/evidence/phase-9/soak.md`; `tools/soak.py` ported to v2).
- [x] Release skill preflight green (unsigned mode; signing, notarization,
      Sparkle keys, and an app icon are owner steps); packaged-app smoke green
      (`BOOP_BIN=build/package/Boop.app/Contents/MacOS/Boop app/tools/headless.sh`
      then `app/tools/e2e-smoke.sh`, 126 passed).
- [x] Contact sheet (`plan/evidence/phase-6/`) and app snapshots
      (`/tmp/buddy-snapshots`, regenerated by the snapshot tests) exist; attaching
      them to a GitHub release is the owner's step since `gh` is not installed.
- [ ] Doctor green from Claude Code, Codex, and Cursor on a clean machine.
      Claude Code: static 8/8 and the live check fired on 2026-09-09 (installed
      hook v4 repairs on the next normal launch). Codex and Cursor: pending a
      person in those harnesses (`app/Tests/Fixtures/hooks/VERSIONS.md`).

**Human steps.** Sign and notarize; a clean-machine install; reset the
board and pair it over BLE for the latency and soak rows; run the doctor
from Codex and Cursor.

**Finding (2026-09-09, UI pass).** The M5StickC environments in
`platformio.ini` have not compiled since Phase 2's v2 renderer: the core
2.x toolchain (GCC 8, mbedTLS 2, older ArduinoJson) rejects brace
initializers and JSON proxies the v2 code relies on. They are the archived
hardware, not a v2 target, so CI builds the shipping board only and the
M5 envs stay in the file for the archived firmware's sake. Re-enable them
only with a deliberate port.

**Finding (2026-09-09, HIL).** `test_shutdown_stages_and_wake_press_guard`
fails only when it runs directly after `test_dim_ladder_and_orb_never_off`,
whose virtual-clock jump (+240 s) is still in effect: after the 3.9 s
secondary hold puts the screen to sleep, the board stops answering serial
for a few seconds and the wake press gets no echo. Alone, or after any
other test, it passes. Not a product path (the virtual clock is a test
tool). Suspect the wake path doing time math on the jumped clock; fix by
making `clock clear` restore real time, or by resetting the clock at the
start of the shutdown test.

**Host-side work landed (2026-09-09).** `VERSION` 1.0.0; CI jobs for the
leaderboard service and every firmware environment plus the host-side
firmware tests; the firmware release workflow points at `firmware/esp32`
and the shipping board; `docs/SUPPORT.md`; the fixture matrix in
`app/Tests/Fixtures/hooks/VERSIONS.md`; headless runs use scratch
preferences (`AppDefaults`) as well as a scratch store.

---

## Cross-cutting, tracked per phase

- **Languages.** Every user-visible string in the app and every authored
  line is keyed for localization from Phase 1; Korean lands with Phase 5
  and the device font with Phase 2.
- **Agent channel.** The MCP tools keep working through every phase;
  Phase 1 maps them to the new overlay, Phase 2 renders the overlay frame.
- **Privacy tests.** From Phase 3 on, every phase's checklist includes the
  "nothing raw written" grep.
- **Documentation.** Each phase updates `archived/research/eng/ARCHITECTURE-APP.md`
  and `archived/research/eng/TESTING.md` to describe what now exists, so the eng docs stay
  source-derived and this plan stays the intent.

---

## Documents still to write before their phase starts

| Document | Needed by |
| --- | --- |
| `UX-APP.md` | Phase 7 |
| `UX-GROWTH.md` (level curve, XP weights, cosmetics schedule) | Phase 4 for mechanism, Phase 8 for schedule |
| `UX-VOICE.md` (line style, sass ceiling, banks) | Phase 5 |
| `UX-HELP.md` (nudge ladder values, stuck thresholds, glosses) | Phase 3 |
| `HARDWARE-V2.md` | Phase 6 |

## Architecture simplification pass, 2026-09-09

Cross-cutting maintenance alongside the Phase 9 gates: moved shared byte
truncation and stakes policy into neutral Core files, without algorithm
changes. `make test` now delegates target selection to SwiftPM metadata and
executes the existing runner on CommandLineTools. Review and follow-up gates
are in [ARCHITECTURE-REVIEW.md](ARCHITECTURE-REVIEW.md). This does not mark
unverified phase checklists complete.

**Growth extraction follow-up.** Growth coordination now owns signing and
leaderboard lifetimes behind capability protocols. The engine retains the
persistence barrier and reducer dispatch. Concurrent sync requests serialize
as a task chain; regression checks exercise disconnect, retirement, opt-out,
backoff, and multiple callers. Final `make test`: 437 passed, zero skipped.
Detailed validation results are in the architecture review.

**Voice/preferences follow-up.** Transient voice slots now have one lifecycle
owner; device output receives consistent preferences for connection, unpairing,
and encoding. Targeted cancellation and preference-isolation checks are part
of the full suite. Diagnostic JSON is captured before the state-projection
migration so its encoding can be compared independently afterward.

**State projection follow-up.** The voice/preferences stage passed 444 checks
with zero skips (including the temporary original-encoder capture). Pet state,
last signal, and celebration intensity are now computed; species remains
independent. The permanent diagnostic fixture comparison replaces that capture
check. Snapshot parity and final suite results are recorded in the review.

**Final verification.** 445 tests passed, zero skipped. The 14-sample diagnostic
JSON fixture matches; 146/147 UI snapshots are byte-identical, with only a
one-level RGB edge variation in 155 pixels of the Korean share card. The image
pair was visually reviewed. Full results are in `ARCHITECTURE-REVIEW.md`.


## Webcam verification mode, 2026-09-10

Added a physical-motion layer beside Phase 0/2/6 screenshot verification:
`make webcam` captures bounded video through native macOS APIs; offline analysis
preserves consecutive frames, timestamps and capture-gap evidence. Procedures
and limitations are in `VERIFICATION.md` §2.1.1 and `tools/webcam/README.md`.
Synthetic-video tests cover the tool. A real Buddy recording was captured and
450 consecutive frames reviewed for boop, hop and dance; see
`evidence/webcam/2026-09-10.md` for results and camera-quality limits. This does not close existing hardware gates.


**Opt-in preference (2026-09-10).** Webcam verification is a reusable
`webcam-verify` skill with implicit invocation disabled. Live capture requires
an explicit request and setup confirmation for that session; it is not part of
ordinary verification or a standing authorization to use the camera.


**Progression reference (2026-09-10).** [XP and skill tree](XP-AND-SKILL-TREE.md)
documents current awards, caps, level thresholds, streak protection and the
unlock ladder, separating equippable cosmetics from inventory-only rewards.
Documentation only; no new progression behavior or phase completion is claimed.


**XP simplification (2026-09-10).** Removed level prerequisites from appearance
availability and equipping. Existing behaviors remain available at all levels;
XP, levels, streaks and keepsakes are bragging-rights statistics. Existing stores
retain awards and selections. `XP-AND-SKILL-TREE.md` supersedes its earlier unlock
ladder description. Verification is tracked in `VERIFICATION.md`.

XP simplification validation: `make test` passed 445 tests, zero skipped.

**Minimal Mac control center (2026-09-10).** Owner-directed Phase 7 revision:
one window with Overview, Activity and Settings; no pet face in ordinary app
content or onboarding. Added XP progress/history, retained approvals and settings,
and kept sharing/recap/collection in Activity. Snapshot and regression validation
are recorded in `VERIFICATION.md`. No webcam session is activated by this work.

Control center validation: `make test` passed 448 tests, zero skipped; offscreen
pane, approval and onboarding snapshots reviewed. Ready for user-launched app
iteration; live window/BLE verification remains separate.

## Parallel development tooling (2026-09-10)

Added per-worktree headless instances and explicit E2E routing, plus a shared
whole-run device reservation with scenario logs and restoration scripts.
The GUI is manually quit/relaunched around hardware runs. No simulator planned.
Software orchestration checks cover lease exclusion/delegation and restoration
after scenario failure; real device verification is still owed. Usage lives in
`tools/dev/README.md`.

Validation: `swift build --product Boop` passed outside the cache-restricted
sandbox. All three workflow tests passed both with a lightweight HTTP fixture
and with two real Boop headless processes (isolated authenticated startup and
clean shutdown, lease exclusion/delegation, restore after failed scenario).
Physical HIL and flashing were not performed.


## Compact device footer, 2026-09-10

Owner-directed first iteration implemented: compact approval footer, persistent action labels, transient hold underline, and no rendered session dots. Shipping firmware builds successfully. Targeted USB hardware checks and visual review passed; normal firmware with the footer is installed (see evidence/device-footer-2026-09-10/README.md).


**Build isolation (2026-09-10).** Waveshare builds now default to ignored
per-worktree `.platformio-core` state. CI caches the same paths. This removes
the home-directory cache write dependency and isolates parallel toolchains;
physical-device reservation is unchanged.

Verified the local-cache shipping build under workspace-only permissions
(97 s rebuild, then 4.7 s warm build). No permission escalation needed.


## USB-only bench verification, 2026-09-10

Independent USB verification now has a compile-time-only firmware target and an explicit runner mode. This enables Mac UI and device UI work in parallel; Bluetooth integration remains a separate coordinated gate. Debug firmware must never be published or left as the shipping image.

**USB-only verification result (2026-09-10):** completed with the Mac GUI
open. Five host workflow checks, the animation-clock guard, and fourteen
distinct targeted device cases passed across runs. Footer captures reviewed,
three card goldens refreshed, saved device state restored, and normal
`dev-footer-20260910` firmware installed with `usbOnly=false`. No BLE
integration gate is claimed by this USB-only run.


## Larger approval face, 2026-09-10

Owner-requested second footer iteration: lower the approval face by 22 px and enlarge its eyes by 20%, preserving the compact footer. Both builds and the animation-clock guard passed. All three approval styles, hold feedback, and confirmation were reviewed on hardware; no text overlap or new panic. Three card goldens refreshed; saved device state restored and normal `dev-face-v2` installed (`usbOnly=false`). Evidence: `plan/evidence/device-face-v2-2026-09-10/`.
