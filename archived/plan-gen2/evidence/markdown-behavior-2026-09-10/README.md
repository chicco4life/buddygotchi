# Markdown behavior controller — 2026-09-10

- `make test`: 392 passed, zero skipped. Injected-runtime tests cover live
  guide reload, owner-edit preservation, silence, fallback, periodic checks,
  approval exclusion, celebration ordering and late-result cancellation.
- `make build`: Boop and BoopSignal passed with the final prompt context.
- Reviewed the current offscreen Buddy Settings snapshot: edit action is visible.
- `git diff --check` passed.
- No live Foundation Models evaluation or Bluetooth app launch. No wire or
  firmware changes in this follow-up.

The guide owns conversational decisions. The reducer still owns states and
celebration behavior; the initial model action surface is a line or silence.
