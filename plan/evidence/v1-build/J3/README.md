# J3: Handoff — evidence

2026-09-26, on branch `v1-overnight`. Webcam off (your 05:36 decision), so
no L3 check ran.

## What was done

- **[REPORT.md](../REPORT.md):** every milestone with its evidence, the
  known issues, the confirmed panel settings, and what the morning
  checklist should do differently.
- **`boopctl calibrate`** (new). The morning checklist and DEVICE.md §4
  named it, but it didn't exist. The board draws an amber cross on
  `dbg.pattern` `target`; the tool reads raw touches from `dbg.state`,
  takes the median of each tap, fits an affine raw → screen map by least
  squares, checks it on a fifth cross in the middle, and sends it with the
  new `dbg.touchcal`. The board applies it (`app/touch_cal.h`, pure C++)
  and keeps it in NVS. With no calibration, the default raw range is used,
  as before. It always puts the board back on the face, even when it stops
  early.
- **Checklist (PLAN.md §6):** row 2 now expects the no-app face, row 3
  describes calibration, and row 4's strip tap moves after the app
  connects.
- Specs: DEVICE.md §4, VERIFICATION.md §2–3, a decision-log row, README.

## Checks

| Check | Result |
| --- | --- |
| L0 `make fw-test` | Passed: 77/77 (3 new: the map with clamping, `dbg.touchcal` set/read/clear, the cross on `dbg.pattern`) |
| The fit, on synthetic taps with skew and ±8 raw noise | Within 0.6 px at the centre and corners |
| On the board: `dbg.touchcal` read, set, **survives a reflash and reboot**, then cleared | Passed ([touchcal-board.txt](touchcal-board.txt)). The board is left uncalibrated for you |
| On the board: the cross | [device-calibration-cross.png](device-calibration-cross.png) at (20, 300) |
| `boopctl calibrate` with nobody tapping | Stops after 60 s with "no tap within a minute", exit 2; after the fix, it returns the board to the face |
| A real calibration | **Not done:** it needs a person (morning checklist row 3) |
| L1 `boopctl sim` | Passed: 10 scenarios, 0 expect failures, 0 new or changed pictures |
| L2 `boopctl run` | Passed: 10 scenarios, 0 expect failures, 0 pictures differ from the simulator |
| `make test` | Passed: 166/166 |
| L4 `make e2e` (rules brain) | PASS |
| Final firmware flashed | `06014a970b` (1.0.0), Bluetooth advertising as `Boop-54FE`, heap 73.6 KB, uncalibrated; the no-app face, as expected with no Mac talking ([device-final.png](device-final.png)) |
| L3 | Skipped: webcam withdrawn |
