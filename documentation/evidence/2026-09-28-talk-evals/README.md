# Talking to Boop never gets ignored (2026-09-28)

The owner asked for more evals on push-to-talk: the person talking to Boop
is the one thing it must never ignore. `35-talk-gets-an-answer` covered one
situation (an agent working, a kind word, a question, an insult). Five new
`always` scenarios each target one way a face could go missing:

| Scenario | What could swallow the face |
| --- | --- |
| `36-talk-when-grumpy` | A grumpy mood from a poke barrage |
| `37-talk-when-idle` | No agent working at all |
| `38-talk-twice-over-a-face` | The face for the first thing said still in progress (`none` is for a face already playing, [DECISIONS.md](../../harness/DECISIONS.md) §5) |
| `39-talk-after-a-failure` | A failed turn; venting isn't rude to Boop, and encouragement shouldn't get a grumpy face |
| `40-talk-garbled-words` | Words that mean nothing, as speech recognition often hands over |

## What ran

| Check | Result |
| --- | --- |
| `boopdev eval --only talk` (Jev), before any steering change | 35–39 passed 5 of 5; `40-talk-garbled-words` 1 of 5: `"the uh so if we"` got no face |
| The fix | One PERSONALITY Example, with other words than the eval's: `You said to Boop: "so the, um".` → happy, "hmm", once |
| `boopdev eval --only talk` (Jev), after | 6 of 6 scenarios pass 5 of 5 runs |
| `boopdev eval` (Jev, every scenario) | 39 of 40 pass every run ([eval.txt](eval.txt)); `20-no-flail` is the known gap. Median latency 244 ms, slowest 866 ms |
| `make -C internal test` | 277 passed |

## Not covered

- Talking while something needs you: the eval runner has no step for a
  permission request, so it would need a new step type.
- The real mic and speech recognition (owner only, `make run`).
