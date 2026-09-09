# UI pass evidence, 2026-09-09

Owner review: "parts of the app don't look nice; the device UI is clunky
and cluttered; make it simple and elegant." Decisions: face only on the
device (no body, no glow), box-less card with a hold ring, native macOS
materials in the app, five settings sections. Specs first
(`plan/UX-DEVICE.md`, `plan/UX-APP.md`), then implementation.

Device cells: the 39 contact-sheet cells captured with `tools/shots.py`
after the final flash; goldens re-recorded and re-checked from a second
fresh capture (39/39, mean error 0). USB HIL: 82 passed. App: 430 unit
tests, snapshots regenerated (`phase7-popover-*`, `settings-*`,
`phase7-profile-*` here for reference; popover captures render centered
in the harness, the live popover sizes to content).
