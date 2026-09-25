# Implementation and verification status

Updated 2026-09-12. The current development build implements the shared behavior
pipeline, optional whole-desk summaries, glanceable device completions and the
quality/fluidity pass. **Live-model meaning, native-editor flows, public OTA and
Bluetooth startup stability still have open gates.**

[How Boop behaves](BEHAVIORS.md) is the current behavior reference.
[Verification](VERIFICATION.md) owns procedures; dated evidence records what was
actually exercised. An implementation or USB pass does not close every live gate.

## Command Line Tools build compatibility (2026-09-25)

Reproduced main's build failure with Apple Swift 6.4 and the macOS 27 SDK:
`@State` selected a macro whose `SwiftUIMacros` plugin is absent from CLT.
Views now use `@ViewState`, an alias for the existing `SwiftUI.State` property
wrapper. `swift build --product Boop` passed in the task worktree and the local
main checkout; the executable retains its embedded Info.plist. The normal test
entry point passed **393 tests**, with **12 opt-in snapshot tests skipped** and
no failures. A focused wrapper/binding typecheck passed against both installed
macOS 27 and 26.5 SDKs. GUI launch and Bluetooth remain owner-run checks.

## Turn moments (implemented 2026-09-12)

[Turn moments](UX-TURN-MOMENTS.md) now uses the existing trigger → shared context
+ editable BEHAVIOR.md → Voice → pure Core/output path. Starts get a brief
acknowledgement; completions use <3-second face, 3–<20-second four-second caption,
and >=20-second full caption-pulling celebration. No mid-work summary pop-ups or
second post-idle completion remark. Mac keeps its whole-desk summary.

Validated `boop-policy` metadata in the same guide owns thresholds, dwell,
coalescing, expressions and optional immediate fallbacks. Default long-work
opportunities are 5/15 minutes with a 2-minute cooldown; person returns use 18
hours and supplied local time. New optional interaction memory excludes background
traffic. The single Voice lane uses 24/48-character ASCII budgets and glyph-fit
validation. Existing owner guides are preserved and inherit policy defaults.

## Working/sleep visibility follow-up (2026-09-12)

Source now shows the sweating working face at every effort level. Sleeping
brightness rises from 28 to 72/255; the 1.4-second local tap response uses awake
210/255 brightness and normal face ink, then returns to 72. Face-down nap stays
28. Concurrent-session intensity scaling remains a later tuning opportunity.
Both firmware variants build. **29 USB checks passed**, including the sleep tap
brightness lifecycle; **19 working/sleep goldens** reproduced twice exactly.
After the user quit Boop, normal **dev-visible-20260912** was installed and
verified in three startup samples: increasing uptime, unchanged panic counter
103 and no safe mode. Saved settings/pairing were preserved.
[Evidence](evidence/working-sleep-2026-09-12/README.md).

## Current implementation

| Area | Implemented |
| --- | --- |
| State and work | Six states; light/hard/grinding effort; guide-policy completion tiers and bounded coalescing |
| Attention | Passive requests; 60/120-second nudges; dismissal per request; editor-only approvals and fail-open hooks |
| Device activity | Working face, coalesced turn moments, paged threads/history; persistent Last finished row removed |
| Mac | Menu-bar Overview, every session scrollable, one Settings form, fixed appearance, Quiet mode |
| Growth | +3 XP per completed started turn, +10 per active local day; cumulative XP, no levels; daily grid and consecutive-day streak |
| Local model | One editable guide and shared display context; Mac scope plus start/completed/long-work/return/error occasions; bounded milestone opportunities, no stock error messages |
| Memory | Reduced facts and private profile reflection; profile is not yet supplied to shared display calls |
| Quality | Pure display projection, consistent session counts, preserved eligible dialogue, smooth interrupted motion/card departures, firmware version confirmation and retry handling |

Richer supported check-result reactions and durable episode callbacks remain
[stages 2/3](UX-WORK-SCOPE.md). Guided-generation experiments are candidates,
not the current runtime. Removed features are not future requirements; optional
possibilities belong in [Ideas](IDEAS.md).

## Earlier readiness follow-up (2026-09-11/12)

[Readiness evidence](evidence/readiness-2026-09-11/README.md) records the latest
model replay, native-editor checks and OTA client fixes. The app suite passed
392 tests with zero skips; both Mac products built. Claude and Codex native
allow/deny checks passed against a temporary headless receiver. The guided model
candidate remains test-only. USB recovered after the user reported a dim face;
its asleep state and brightness 28 were confirmed. Three software restarts
left panic count unchanged at 103. Actual Mac OTA then passed: normal BLE
firmware `0.0.1-readiness.1` was installed, with secure reconnection and unchanged
panic count after over 100 seconds. Startup root cause and public delivery remain
open. The local transfer took about 18 minutes; hide/reopen passed.
The newer working/sleep installation below supersedes that OTA candidate.

## Latest evidence

| Check | Result and scope |
| --- | --- |
| Main integration (2026-09-12) | **405 app tests passed, zero skipped**; both Mac products built; 6 workflow tests and 1 release-artifact test passed; readiness privacy/hook/OTA fixes retained |
| Turn moments (2026-09-12) | **396 app tests passed**, both Mac products and firmware variants built; **48 USB checks**, 27 lifecycle captures, 14 independently repeated goldens; normal candidate subsequently installed at user request |
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

Evidence: [turn moments](evidence/turn-moments-2026-09-12/README.md),
[quality and integration](evidence/quality-fluidity-2026-09-11/README.md),
[Apple API experiment](evidence/foundation-models-api-2026-09-11/README.md),
[footer removal and installation](evidence/remove-last-finished-2026-09-11/README.md).

## Installed versus built

**Working/sleep visibility normal firmware is installed**, at the user's request
after they quit the Mac GUI: `dev-visible-20260912`, git `0c7f1d0e9b1a`, `usbOnly:false`.
The final install wrote application and boot selection, preserving saved NVS
settings/pairing. Three startup samples showed increasing uptime and unchanged
panic counter 103, without safe mode. This supersedes `dev-moments-20260912`; no USB-only debug image is installed.

Both Mac products are built and the bundled behavior guide matches current source.
The agent did not launch the GUI; the user was given the matching worktree's
`make run` command. Owner Markdown overrides remain intact and inherit policy
defaults when metadata is absent. No public release or post-install production
Bluetooth behavior check was performed. See [installation evidence](evidence/working-sleep-2026-09-12/README.md#installed-status).

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

## Earlier device phrase readability follow-up (2026-09-12)

Candidate change: brief larger phrases below a subtly raised/smaller face,
four-second fade lifecycle without replay, and a bottom-right busy/idle hint.
The Mac retains scope; the bundled model guide asks for 3–6 compact words.
Both firmware variants build. All 31 USB scope/navigation checks passed; after
a final UTF-8 bounds guard, 9 focused scope checks passed again. Sixteen lifecycle
screenshots were inspected; eight affected goldens reproduced twice exactly.
The attached device's previous normal image was `0.0.1-readiness.1`
(`0c7f1d0e9b1a`); it was restored after this initial test. The phrase-only
candidate was not installed for everyday use. The later turn-moment and visibility
work above supersedes this prototype. Owner guide edits were preserved.
See [phrase evidence](evidence/device-phrase-2026-09-12/README.md).
