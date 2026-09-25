# A3: Harness and brains — Blocked

**Blocked on:** the L5 sample review with Apple's on-device model
(`apple:27.0`). The harness, the rules brain and everything L0 checks pass.
The brain's numbers pass too. Its judgement doesn't yet.

## What passes

- **L0:** `make test`, 135/135. Harness tests with a fake brain cover shape
  rejection, cancel, replace and at most 3 calls. Apple's schema builds for
  every trigger, and `none` handling is tested.
- **L5, rules brain** (`l5-rules.txt`): 52/52 valid, 0 dropped, PASS.
- **L5, Apple's model, numbers** (`l5-apple-run2.txt`): latency p95 is
  2.0 s for events, 2.0 s for taps, 2.3 s for talk and 3.6 s for
  reflection, all under their deadlines. Actions dropped 2 of 86 calls
  (2.3%).

## What fails

- **Valid shape is 50/52**, not 100%. Both misses are Apple's guardrail
  refusing the answer ("Response may contain sensitive or unsafe
  content"). They happen on prompts about "jetpack is the payments
  service", even with `permissiveContentTransformations`. The harness
  drops a refused answer like any brain error, so Boop just stays with the
  core's rule reaction. That's safe, but it doesn't meet the check as
  written.
- **The review:**
  1. **Talk misuses `note`.** It notes praise and greetings: "good job
     today", "you're the best" and "good morning" each get a note, and
     sometimes it's a copy of an existing one ("jetpack is payments").
     "remember I ship on Fridays" sometimes gets no note at all.
  2. **The `tests` filler.** 18 of 52 answers mumble `word: tests`,
     including plain taps. The sample's temperament ("Gets huffy about
     flaky tests") seems to pull it in.
  3. **Rarely quiet.** Only 4 of 50 answers were silent. Nearly every
     event gets a face plus a mumble.
  4. **Reflection:** it now remembers the right fact ("jetpack is
     payments"). But it writes a `moment` every day, and one of them was
     "flaky tests keep rising".

## What was tried (this iteration and the last)

| Change | Effect | Kept |
| --- | --- | --- |
| A flat "slots" schema, one optional property per tool | Filled every slot, over the call limit | No |
| A leading `react` choice | Some silence (was none) | Yes |
| A `none` first in every choice | Fewer filler words on greetings; `tests` still common | Yes |
| Steering examples: turn started → nothing; praise; late taps; notes rules | Small, inconsistent gains | Yes |
| A reflection example with a `remember` | The model copied the example text into memory | No |
| Taking `forget` out of reflection | The true fact is no longer deleted | Yes (ARCHITECTURE §11) |
| A realistic fixture: notes are the person's facts, not agent news | Reflection remembers the right fact | Yes |
| `moment` refuses a retelling of an earlier moment | The copied moment is dropped | Yes |
| A leading free-text "thought" field | Worse talk and reflection; tap p95 3.0 s, at the deadline | No |
| Greedy sampling | More `tests`, fewer silences | No |

## Best guess

The ~3B on-device model can't follow a 790-token steering file closely
enough to decide *whether* to act and *which* tool to use. Constrained
choices fix the shape, but not the judgement. What would likely work:

1. **Take judgement out of free choice.** Let the core decide whether the
   brain speaks at all for events (e.g. only long finishes and first
   starts). Offer `note` only when the words look like a fact ("remember",
   "note", "X is Y"). That's a spec change to HARNESS §5 and the core, so
   it's the owner's call.
2. **Two-step reflection:** first ask a yes/no question per tool, then ask
   for the text.
3. **The owner's review.** Much of this is taste. The owner may decide the
   current behaviour is fine for v1 with the rules above. Or they may
   accept the guardrail refusals as silent drops and change the
   "100% valid shape" check to count only answers the model gave.

A4 and J1 don't depend on this. They use the harness, which passes, and
the brain setting can be `rules` until this is settled.
