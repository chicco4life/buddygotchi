# Implementation and verification status

Updated 2026-09-12. The current development build implements the shared behavior
pipeline, optional whole-desk summaries, glanceable device completions and the
quality/fluidity pass. **Live-model meaning, native-editor flows, public OTA and
Bluetooth startup stability still have open gates.**

[How Boop behaves](BEHAVIORS.md) is the current behavior reference.
[Verification](VERIFICATION.md) owns procedures; dated evidence records what was
actually exercised. An implementation or USB pass does not close every live gate.

## Current implementation

| Area | Implemented |
| --- | --- |
| State and work | Six states; light/hard/grinding effort; duration-based celebrations and 3-second folding |
| Attention | Passive requests; 60/120-second nudges; dismissal per request; editor-only approvals and fail-open hooks |
| Device activity | Working face, coalesced completion notices, paged threads/history; persistent Last finished row removed |
| Mac | Menu-bar Overview, every session scrollable, one Settings form, fixed appearance, Quiet mode |
| Growth | +3 XP per completed started turn, +10 per active local day; cumulative XP, no levels; daily grid and consecutive-day streak |
| Local model | One editable guide and shared display context; optional English scope/greeting/error/post-celebration text; no timed check-ins or stock failure messages |
| Memory | Reduced facts and private profile reflection; profile is not yet supplied to shared display calls |
| Quality | Pure display projection, consistent session counts, preserved eligible dialogue, smooth interrupted motion/card departures, firmware version confirmation and retry handling |

Richer supported check-result reactions and durable episode callbacks remain
[stages 2/3](UX-WORK-SCOPE.md). Guided-generation experiments are candidates,
not the current runtime. Removed features are not future requirements; optional
possibilities belong in [Ideas](IDEAS.md).

## Current readiness follow-up

[Readiness evidence](evidence/readiness-2026-09-11/README.md) records the latest
model replay, native-editor checks and OTA client fixes. The app suite passed
392 tests with zero skips; both Mac products built. Claude and Codex native
allow/deny checks passed against a temporary headless receiver. The guided model
candidate remains test-only. USB recovered after the user reported a dim face;
its asleep state and brightness 28 were confirmed. Three software restarts
left panic count unchanged at 103. Actual Mac OTA then passed: normal BLE
firmware `0.0.1-readiness.1` is installed, with secure reconnection and unchanged
panic count after over 100 seconds. Startup root cause and public delivery remain
open. The local transfer took about 18 minutes; hide/reopen passed.
The installed-version and GUI statements below describe the preceding session.

## Latest evidence

| Check | Result and scope |
| --- | --- |
| App tests after optional dialogue change | **383 passed, zero skipped**; Boop rebuilt |
| Broad quality pass | 382 preceding app tests, 105 isolated HTTP checks, 6 workflow tests; both Mac products and both firmware variants built |
| USB hardware quality | All 100 non-BLE scenarios passed across a full run and the targeted settling recheck; 52 goldens reproduced twice at zero error |
| Bounded webcam motion review | Final consecutive-frame review confirmed the card-footer departure fix; session complete |
| Owner-launched app / Codex hooks | Doctor: 8 OK, no failures/warnings; synthetic and actual Codex hook round trip passed |
| Production Bluetooth behavior | 15 coordinated assertions passed: dismissal/keepalives/new requests, host answer clear, Quiet mode round trips and reconnect |
| Bluetooth startup stability | One unexplained initial panic increment; not reproduced in **11 confirmed** follow-up reboot/reconnect cycles. Functional pass is not stability sign-off |
| Last finished removal | Both firmware builds passed; **29** dashboard/scope hardware checks passed; 5 scenes independently reproduced at zero error, only 3 footer-bearing goldens changed |
| Release packaging | ESP32-S3 layout and boot-selection image corrected; artifact test and real-image dry run passed; nothing published |
| Real Foundation Models | Scope samples still omit meaning or misinterpret intent. Guided structure improved cross-project coverage in 12 synthetic samples, but did not close semantic quality |

Evidence: [quality and integration](evidence/quality-fluidity-2026-09-11/README.md),
[Apple API experiment](evidence/foundation-models-api-2026-09-11/README.md),
[footer removal and installation](evidence/remove-last-finished-2026-09-11/README.md).

## Installed versus built

The local OTA candidate **normal BLE** firmware is installed and connected:
`0.0.1-readiness.1` (source `0c7f1d0e9b1a`). It preserves the footer removal and
passed secure reconnection and a bounded post-update uptime check. No USB-only
debug image was left installed.

The user launched the readiness Mac app for the successful OTA test. The later
duration wording change was rebuilt but is not in that running process. Owner
Markdown overrides were preserved. The local test server was stopped; the
process-only manifest override clears on a normal app launch. Nothing published.

## Remaining gates

| Gate | What remains |
| --- | --- |
| Model quality | Evaluate relevance, whole-desk coverage, silence, factuality, private-text handling and latency on real English inputs |
| Native editor integration | Exercise actual approval UI, stale-hook passthrough and hook repair in supported Claude/Codex/Cursor versions; HTTP fixtures and the live Codex hook check cover only part of this |
| Startup stability | Explain or reproduce the initial firmware panic before a clean stability sign-off |
| Public OTA delivery | Local actual Mac OTA passed; public manifest remains HTTP 404, so hosted delivery is still unverified |
| Release readiness | Clean install/update, supported environments, signing/notarization, overnight hardware/power checks and applicable release procedures |

## Earlier evidence

These records describe earlier builds and may contain superseded behavior or
restoration status. Use the tables above for the latest result.

- [Shared scope implementation](evidence/work-context-2026-09-11/README.md) and [main integration](evidence/work-context-main-integration-2026-09-11/README.md).
- [Glanceable completions](evidence/glance-completions-2026-09-11/README.md), [detail navigation](evidence/dashboard-navigation-spacing-2026-09-11/README.md), and [earlier dashboard](evidence/agent-dashboard-2026-09-11/README.md).
- [UI pass](evidence/ui-pass-2026-09-11/README.md), [compact Overview](evidence/compact-overview-2026-09-11/README.md), [cumulative XP](evidence/cumulative-xp-2026-09-11/README.md), and [essentials](evidence/essential-behaviors-2026-09-11/README.md).
- [Native approvals / Markdown behavior](evidence/markdown-learning-native-approvals-2026-09-11/README.md), [simplification](evidence/behavior-simplification-2026-09-11/README.md), and [share removal](evidence/no-share-2026-09-11/README.md).
- [Original phase history](PLAN-HISTORY.md).
