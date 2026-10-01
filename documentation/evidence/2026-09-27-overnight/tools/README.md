# Overnight 2026-09-27: tools lane

Fewer, integrated commands (branch `ovn/tools`). What was checked, on this
Mac, with no board, camera or Bluetooth:

- `make build`, `make test` (212 passed), `make eval` (24/24, chatty and
  calm, no writer), `make sim` / `tools/boopctl sim` (10 scenarios, 0
  expect failures, 0 changed pictures), `make tools-test` (boopctl's
  commands and the webcam recorder).
- `skills/doctor/doctor.sh --headless`: 5 passed, and the same through the
  `.claude/skills/doctor` link. `--confirm` against a fake log: an earlier
  day's hook line no longer passes it; a new one does. With a temporary
  HOME whose hooks call a deleted app copy of `boop-hook`, it reports that
  copy missing (not outdated hooks).
- Debug mode end to end: `Boop --headless --state-dir /tmp/… --mode chatty
  --writer none --debug`, fixture hooks through `boopdev replay --socket`,
  then `boopdev talk`. [debug-sample.txt](debug-sample.txt) is what its
  terminal printed (trimmed). What was said reached the terminal and
  `debug.jsonl`, not `boop.log`. `boopdev watch` on that `debug.jsonl`
  across a relaunch printed one "started again" line, then the second
  launch's passes.
- `make eval REAL=1`'s wiring, dry: `boopdev eval --real --writer none
  --runs 1` with no `BOOP_JEV_KEY` ([eval-real-dry.txt](eval-real-dry.txt)):
  normal is skipped with one line, the summary leaves out the steps that
  script a stage (05-bad-answer's scripted crash counted against the
  brains before the review caught it; `EvalSummaryTests` pins it now), and
  it holds, exit 0. Apple's model wasn't run here (the brain lane owns it
  tonight).
- `boopdev replay app/Tests/Fixtures/hooks/e2e/claude/session.jsonl
  --socket …` against a headless app: 13 s, where it used to sleep through
  440 s of `advance_ms`.

Not checked: `make e2e` and `boopctl soak --pipeline` (they need the
board; e2e.py now passes `--debug` and reads `state/debug.jsonl`), and
the menu-bar app's `--debug` (it would need Bluetooth).

Found on the way: `swift build` in `app/` alternates between a no-op
(0.4 s) and a 6–9 s rebuild with nothing changed, so build timings are
noisy until that's found.
