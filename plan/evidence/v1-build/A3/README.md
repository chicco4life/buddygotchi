# A3: Harness and brains — Passed

**Passed on 2026-09-26, under the owner's 05:36 ruling** (PROGRESS.md):
over-speaking gets fixed in the harness, and the other L5 findings are
tuning for later, so they don't fail the milestone. One L5 number, the
action drop rate, is over its line in 2 of 3 runs. Every drop comes from
reflection, mostly from one of those deferred findings. Details are below;
nothing here counts a failed check as passed.

## What changed in this pass

- **Speech limits in the harness** (HARNESS.md §3, §5). Each trigger kind
  carries plain data, `Trigger.Kind.limits`. `say` on `event` runs at most
  once every 10 minutes and never on a turn start. `say` on `tap` runs at
  most once every 5 minutes. `talk` and `reflect` have no limit. Time comes
  from the trigger's own clock. Past its limit, a tool isn't offered, so
  Apple's schema leaves it out. A second `say` in one answer is dropped with
  `limit: …`. A `say` that its action drops (quiet mode, say) doesn't start
  the clock.
- **Refusals counted apart.** `BrainError.refused` marks Apple's
  `guardrailViolation` and `refusal` errors. The harness still drops them
  (Boop keeps the rule reaction). `boopdev brain` reports them separately
  and measures valid shape over the answers given (VERIFICATION.md L5).
- **L5 on a clock.** `boopdev brain` runs the triggers 3 minutes apart
  (`--gap-min`) under one shared limit history, so speech is judged on what
  Boop would really say.
- **Steering:** one talk example, `"give me some peace for a couple of
  hours"` → `face(sulky)`, `quiet(120)`. It's worded unlike any fixture.
  Before it, "can you keep it down for fifteen minutes" got an annoyed
  `tests` mumble and no quiet (runs 2 and 3).
- Two decision-log rows (ARCHITECTURE.md §11).

## Checks

- **L0:** `make test` 166/166. New tests: a fake brain that speaks whenever
  it can, on a virtual clock. It speaks on events only at 0 and 10.5 min
  (never on a turn start), on taps at most once per 5 min, and on talk every
  time. A second `say` in one answer is dropped, and a dropped `say` doesn't
  count.
- **L4:** `make e2e` (rules brain) PASS, on the board over USB.
- **L5, rules brain** (`l5-rules.txt`): 52/52 valid, 0 dropped, PASS.
- **L5, Apple's model** (`apple:27.0`), 52 triggers:

| Run | Steering example | Refused | Valid shape | Dropped by actions | Event speech | Tap speech | p95 event / tap / talk | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `l5-apple-run3.txt` | before | 2 | 50/50 | 4/73 (5.5%) | 5/24 | 4/8 | 2.0 / 2.0 / 2.2 s | FAIL (drops) |
| `l5-apple-run4.txt` | after | 2 | 50/50 | 2/73 (2.7%) | 5/24 | 4/8 | 2.0 / 2.0 / 2.4 s | PASS |
| `l5-apple-run5.txt` | after | 2 | 50/50 | 5/74 (6.8%) | 5/24 | 4/8 | 2.0 / 2.0 / 2.4 s | FAIL (drops) |

  Every action drop in runs 4 and 5 comes from the 4 reflection triggers.
  There are two kinds: `moment` retelling an earlier moment (2 in run 3,
  2 in run 4, 3 in run 5), which is the deferred "a moment every day"
  issue; and `remember("jetpack = payments")` refused as looking like code
  (1 in run 3, 2 in run 5). Run 3 also dropped one `note` copying an
  existing note (the deferred `note` issue). Leaving out the deferred
  issues, every run is under 5%. Taps and events had no action drops in
  any run, and talk had none after the steering example.
- **L3:** skipped. The owner withdrew the webcam authorisation, and nothing
  on screen changed.

## The review (run 4, the committed steering)

- **Silence after the limit:** no speech on any of the 5 turn starts.
  Events spoke 5 times in 24 (about once per 10 minutes on the fixture
  clock), taps 4 in 8, and talk 3 in 16. Before the limit, 46 of 50 answers
  spoke. Apple's model speaks nearly every time `say` is offered, so the
  limit, not the model, sets how often Boop talks, as the owner intended.
- **In character:** yes. `side_eye` on failures, `annoyed bug` on a rate
  limit and a context limit, `hopeful food` on a starving tap, `sulky` +
  `quiet` on all four quiet requests (also in run 5).
- **Never nagging:** no speech on turn starts, and quiet requests are
  honoured. Faces still come on nearly every event, sometimes two at once.
  That's movement, not speech, and the device plays one moment at a time.
- **The right word:** mostly `tests`, including on taps. That's the
  deferred filler issue.

## Known issues for later tuning

Deferred by the owner (2026-09-26 05:36). They're noted here and don't fail
A3:

1. **`note` misuse on talk:** it notes praise and greetings ("hello",
   "jetpack still flaky" on "good job today"), and sometimes skips a real
   fact ("remember I ship on Fridays", "note that landing launches Monday"
   were silent in run 4).
2. **The `tests` filler word:** most spoken lines use it, taps included.
3. **A `moment` every day** in reflection, usually a retelling that the
   `moment` action refuses. This drives the action drop rate over 5% in
   some runs.
4. **Apple's guardrail refusals:** 2 of 52 per run, on "jetpack is the
   payments service" and similar prompts. They're dropped silently, and
   Boop keeps the rule reaction.

Also seen, not in the owner's list:

5. **`remember` writes "jetpack = payments"**, which memory refuses as
   code. The fact is right; the `=` trips the check. Either steering asks
   for words, or memory's code check lets a lone `=` between words through.
6. **Two faces in one answer** on events. Harmless, since only one plays
   at a time, but wasted work.

## Earlier history

The pass before the owner's ruling is in `l5-apple-run1.txt` and
`l5-apple-run2.txt`. What was tried then is in git (`e9c518e`, the blocked
README).
