# Jev-only harness (A10), 2026-09-27

The harness rework in [plan/harness/](../../harness/HARNESS.md): typed
events from the core, a typed transcript, a plain-text state, two actions
(`mood`, `react`) asked in one Jev request, and personalities in place of
modes.

## What ran

- **`make test`:** 204 tests pass, among them the core's events
  (`EventTests`), the harness, state text, actions and Jev's wire format
  (`HarnessTests`), the runtime end to end with a scripted brain
  (`RuntimeTests`, including a pass that turns Boop grumpy and the next
  pass reading the grumpy MOOD file) and the eval runner (`EvalTests`).
- **`make tools-test`:** passes, with `boopctl e2e` and `soak --pipeline`
  taking `--brain scripted|jev`.
- **`Boop --snapshots`:** every pane renders; Settings shows the
  Personality picker and, without a key, "only cheers, wiggles and
  chatters by rule".
- **Headless, `--brain scripted --personality chatter --debug`,** with
  `boopdev replay --socket` sending the recorded Claude session through
  the real `boop-hook`: every event woke a pass, mumbles queued behind the
  rule cheer, the turn end read "10 tools. Tests passing.", and
  `boop.log` held none of Jev's state.
- **`skills/doctor/doctor.sh --headless`:** the round trip passes. It
  reports Codex's hooks as outdated on this Mac, because the installer
  now adds Codex's `Interrupt` hook; the everyday app adds it on its next
  launch.
- **`make eval` against Jev,** with the owner's key in `BOOP_JEV_KEY`: 7/7
  scenarios passed in all 3 runs; median latency 226 ms, slowest 390 ms,
  against the 1.25 s deadline. Without the key it exits with "needs its
  API key in BOOP_JEV_KEY".

## What Jev did

[eval-passes.txt](eval-passes.txt) is every event, pass and action of the
3-run eval, from `boopdev watch`. The tests-fight-back scenario plays out
as [EXAMPLE.md](../../harness/EXAMPLE.md) describes: quiet on the first two
failures (answering "oops", then "again", below a mumble), then on the
third `mood: grumpy 1.00`, `react: annoyed 1.00`, "…again!" (0.96), and on
the pass `mood: cheerful`, `react: proud 0.98`, "…finally!" (0.99).

Not run here: `make e2e` (L4) needs the board on USB, and checks 12–17 in
[PLAN.md](../../PLAN.md) §2 are the owner's.
