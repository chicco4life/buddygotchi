# Menu bar companion review — 2026-09-10

Actual SwiftUI captures from `SnapshotHarnessTests.testMenuBarCompactCatalog`.
The overview's XP, level, task count and session are test fixtures, not production
user data. Production reads the engine's live growth/session state.

- `overview-light.png`: 360 × 450 pt Overview, no creature or sidebar.
- `quiet-mode-dark.png`: sound-only Quiet mode in Settings, 360 × 560 pt.
- `setup-device-light.png`: compact device setup with Skip for now.

Reviewed overview, settings categories, approvals and compact setup in both
system appearances. All 449 tests ran: 445 passed, four localhost tests skipped
by the sandbox. Those four passed in the earlier 448-test unrestricted run.
Final Boop product build and Waveshare firmware build passed.
M5 compiles/links with C++17 but fails the flash-size gate (1,770,825 bytes versus
1,572,864 bytes available). No device was flashed and no live GUI was launched.

## Settings follow-up

`settings-all-light.png` is the current settings viewport. `settings-full-dark.png`
shows the entire continuous form in a tall verification capture. There is no
category dropdown; `quiet-mode-dark.png` above records the superseded first pass.
All sections, including appearance and profile, share one scroll.

`settings-with-pending-request.png` verifies that a pending approval does not
appear in Settings. The same fixture shows its approval on Overview.


## Settings simplification — 2026-09-10

Latest Settings revision: `settings-simple-light.png` and `settings-simple-full-dark.png` supersede earlier Settings captures. They show automatic dialogue (no picker), fixed sound/appearance (no controls), Report a bug, and removal of Reset/Retire. The final build additionally applies plain styling to inherited profile/sharing buttons.
