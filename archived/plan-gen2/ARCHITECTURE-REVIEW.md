# Architecture review — 2026-09-09

The active design is sound: normalized hook input, extraction, a pure reducer,
and state-derived outputs. Keep these boundaries. Most complexity comes from
features accumulating in the engine, compatibility projections, and verification
paths that no longer agree with their documentation. A rewrite would put
approval survival, asynchronous persistence, and device compatibility at risk.

## Implemented in this pass

- `Core/UTF8Text.swift` now owns character-safe byte truncation. Server input,
  Voice, onboarding, the engine, and the wire encoder all use it; locating it
  inside the ESP32 output inverted the conceptual dependency. Code moved unchanged.
- `Core/CardStakes.swift` owns the shared command-risk policy used by extraction,
  gloss generation, and reducer fallback. Code moved unchanged; control-character
  handling, classifications, and nudge behavior are preserved.
- `make test` uses `tools/test.py` to inspect the target selected by
  `Package.swift`. It executes XCTest or regenerates and executes the existing
  shim runner. Removed the duplicate Xcode detection and obsolete compile-only
  branch, including its special handling of linker failures.

## Growth extraction follow-up

Implemented priority 1 below: `GrowthCoordinator` owns enrollment, signatures,
retry policy, sync tasks, and retirement draining. `GrowthStore`,
`DeviceReplySigner`, and `GrowthDeviceOutput` remove concrete store/output casts
from coordination. Engine methods retain their public API, and persistence
barriers and reducer delivery remain explicit callbacks. Seven race and wiring
checks were added. Three or more sync callers now form a serial task chain;
previously callers waiting on the same task could resume into competing syncs.

## Voice, preferences, and state follow-up

Voice task cancellation is now centralized in `BehaviorTasks` (the work-scope
implementation replaces `TransientVoiceTasks` with one shared display worker), retaining
independent gift/bubble lifetimes. The engine still decides occasions, prompt
suppression, and delivery events. `ESP32Output` now uses one injected preferences
instance for UUID lookup, unpairing, normal frames, and test-celebration frames;
app and snapshot composition roots pass their matching preferences explicitly.

The state audit found three exactly derivable legacy values: `pet.state`,
`lastSignal`, and `celebrateIntensity`. Species is independent data; prompt,
effort tier, and greeting metadata retain information absent from the creature
and should remain. The migration preserves all 36 diagnostic JSON fields and
nil omission against a baseline captured from the original synthesized encoder.

The goal/file tally bound remains a retention-policy question. Exact counts
for an unlimited number of distinct keys cannot be kept in bounded memory.
Discarding or approximating these counts would change behavior; moving them to
disk would change the memory-only policy. No such tradeoff is introduced here.

## Recommended order of larger changes

| Priority | Evidence in active code | Simplification | Preservation gate |
| --- | --- | --- | --- |
| 1 — implemented | `Core/BuddyEngine.swift`: signing, identity, submissions, retries, rank reads, and settings live beside approvals and reducer dispatch; repeated `store as? Store` and concrete `ESP32Output` lookup | Give growth coordination one owner with narrow store/signing capabilities. Keep device input routing and reducer dispatch in the engine. Move the existing generation checks and task ownership together. | Signing and leaderboard tests; disconnect/reconnect during signing; retire and opt-out during requests; repeated submissions and failures |
| 2 — implemented | `BuddyState` stores both `creature` and legacy `pet`; `aggregate` assigns legacy state, intensity, and last signal from the creature | Inventory consumers, then derive compatibility fields at the serialization/presentation boundary. Preserve existing diagnostic JSON until its consumers migrate. Do not merely delete the old vocabulary. | Reducer and MCP tests, existing diagnostic JSON, desktop snapshots, v2 encoder tests |
| 3 — implemented | `BuddyEngine` repeats gift/bubble task cancellation and revision management in stop, settings changes, and voice scheduling | Introduce one small transient-voice task owner for cancellation and stale-result rejection. Keep gift and bubble lifetimes distinct. | Voice timing tests, language/runtime changes during generation, prompt arrival and gift collection during generation |
| 4 — implemented | `ESP32Output` reads `UserDefaults.standard` but unpairs through `AppDefaults.shared`; frame mapping also defaults to standard preferences | Inject one preferences instance into output and mapping. Keep normal-user defaults and scratch headless defaults explicit. | Saved-device lookup, unpair, sound/name frames, scratch-default isolation |
| 5 | Firmware `main.cpp` combines input handling, rendering, telemetry, serial debug commands, and boot; `data.h` defines model and persistence together | Separate debug command handling and telemetry first; keep USB and BLE feeding the existing shared frame parser. Move ownership explicitly before adding translation units: header-level `static` model/clock variables must not become independent copies. | Host clock guard, USB parser tests, unchanged STATE replies, BLE round trip, framebuffer comparison |

Splitting the engine into extension files alone would improve navigation but
would not remove its concrete dependencies or competing task lifetimes. Prefer
one extracted responsibility at a time over a generic service framework.

## Additional findings

`SessionWindow.pending` is capped at 400, but `goals` and `edits` dictionaries
grow with unique command signatures and filenames. The architecture's bounded
window claim is therefore not a complete memory bound. Fixing this requires a
documented retention policy that preserves attempt and repeated-edit semantics;
blind eviction would reduce functionality.

The plan still contains archived command references, historical hardware names,
and unchecked gates alongside later evidence. Treat `PLAN.md` as a ledger of
evidence, not proof that every listed behavior has been verified. The app README
and test entry-point documentation are corrected in this pass; a full historical
documentation rewrite is separate.

Keep the existing shared wire/SQLite packages, pure reducer, asynchronous store
queue, and common firmware frame parser. Duplication between `archived/` and the
active tree is intentional historical isolation, not a refactor target.

## Verification

- Final voice/preferences/state pass: `make test` passed **445 tests, zero
  skipped**, including eight new permanent cancellation, preferences, and
  projection checks. The intermediate voice/preferences stage passed 444
  checks, including the temporary baseline capture.
- Diagnostic JSON: 14 samples match the pre-migration fixture exactly as JSON
  values, covering all 36 fields and omitted nil optionals.
- Snapshot comparison: 146 of 147 PNGs are byte-identical. The Korean share
  card differs at 155 of 756000 pixels, by at most one RGB level per channel;
  both images were inspected, with unchanged text/layout and differences
  confined to creature edges. This is consistent with rasterization noise.
  Results: [snapshot-comparison.json](evidence/architecture-refactor/snapshot-comparison.json).
- Device preferences are tested through the actual output frame encoder and
  isolated preference suites. This pass does not change firmware or the v2
  wire format, and does not claim a new physical BLE round trip.

- Growth extraction: final `make test` passed 437 tests with zero skips, including
  seven new wiring, lifecycle, and concurrency checks. The earlier USB findings
  below still apply; this follow-up changes no firmware or wire format and did
  not reflash or rerun physical BLE checks.
- Initial cleanup: `make test`: 430 passed, zero skipped, using the generated CommandLineTools
  runner outside the filesystem sandbox. Includes the existing wire, extractor,
  approval, voice, store, leaderboard, and snapshot tests.
- Test entry-point dispatch and nonzero-exit propagation checked for both
  target types; the full-Xcode branch itself was not executed on this CLT host.
- Firmware host checks: five passed (signature verification and presentation
  clock guard), using `/private/tmp/hilvenv/bin/python`.
- Connected hardware: `ws-amoled164`, contract 2, firmware `dev+7cd442caf364`.
  Initial ping reports 198244 bytes free heap and a cumulative panic counter
  of 101. That counter alone does not establish a failure in this run.
- Focused USB HIL: 12 passed, one failed, 65 deselected in 28.86 s.
  Six-state rendering, parameters, field rejection, and frame-limit recovery
  passed. `test_version_reject_and_unknown_keys` observed `needsYou` instead of
  the injected `working` after correctly observing four rejected frames. This
  is consistent with a concurrent host writer, which the suite explicitly
  excludes, but the writer was not independently traced. Treat preservation
  of the last good frame as inconclusive in this live configuration; repeat
  that check with the host output paused before claiming a clean USB suite.
  Firmware is unchanged by this pass; these checks characterize the installed
  build, not a new flash. BLE and visual hardware review were not performed.
