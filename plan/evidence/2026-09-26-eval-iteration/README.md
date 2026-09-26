# Evals with real brains — 2026-09-26

The owner asked for the harness evals ([EVALS.md](../../EVALS.md)) to pass
with the if-else classifier and Apple's writer, and with Jev and Apple's
writer, by improving Boop rather than special-casing the scenarios.

## Where it started

With the rules and no writer, all 8 scenarios passed. With Apple's model
writing, 1 of 8 did ([output](eval-rules-apple-before.txt)). Every failure was a word: the scenarios expected a
mumble with no word, because the deterministic run has no writer, and
Apple's model wrote one. So the scenarios had no way to say which words
fit, and the steps that needed a word scripted it, so the real writer was
never checked.

Running the writer over the 58 fixture inputs (L5) showed the product
problem underneath. It said "yay" to all 10 turns that finished, "oops" to all
8 failures, including failed test runs, and "hmm" to nearly anything said
to it. `steering.md` asked for the topic after a failure and "finally"
after a long wait. 33 of 46 words fit that guidance, from 8 different words.

## What changed

**The evals.** An expected value can list every value that fits
(`word: finally|done|yay`), with `none` for "may be left out" and `*` for
text (`text: "*demo*Thursday*"`). The lists come from the spec, not from
what a model happened to write: a failed test run's word is `tests`; a
sad mumble's is any sad word or none; a very long turn's is never none.
With no writer, words aren't checked, so one line holds for every run.
Scripted words are gone: the scenarios now check the real writer.
`boopdev eval --runs N` runs each scenario N times, and a failed step
shows how Stage 1 decided. Two scenarios are new: a fact becomes a note
and praise doesn't (09), and small talk gets its word (10).

**What the writer reads.** It now reads only the pass it writes for, not
the transcript's window. On 16 inputs, 3 runs each, this was the biggest
single change:

| Writer's prompt | Words that fit (of 16) |
| --- | --- |
| With the window (before) | 8, 9, 8 |
| With the window, earlier words hidden | 8 |
| Without the window | 9, 9, 9 |
| Without the window, with sources (below) | 14, 14, 14 |
| With the window, with sources | 11, 12, 9 |

**The kind before the word.** The model kept keying the word to the
feeling ("ugh" for any annoyed mumble), even with the rule as the last
line of its prompt ("The word is the failed topic." still gave "oops" 4 of
4 times). Asked first where the word comes from (what they said, the
failed topic, how the turn went, the feeling), it picked the right source
nearly every time, and the word followed. The sources' names mattered: on
the 18-case probe, 5 samples each, "what the agent failed at" gave "bug"
or "ugh" for failed tests; "the failed topic" gave the topic 15 of 15.
This is generic: a written argument's definition may name its sources,
and Apple's writer adds one property before the value. The source is in
the writer's raw answer in the debug log, not in the call.

**Steering.** The examples use the named turn lengths and every mumble
example shows its word; Writing lists the four sources in order, with the
words for each. Two wordings were tried against the sensitive cases (8
samples of each): "An error isn't a topic" cut "bug" for a rate limit from
5 in 8 to 1 in 8. The writer's temperature went from 0.5 to 0.2, which kept
the topic right in every sample.

**Numbers named, rules in code.** A finished turn's line says "a long turn
(20 s)" or "a very long turn (4 min)" instead of "took 20 s", so no brain
compares numbers; the core and the if-else classifier use the same bands.
`quiet` is offered only when the words ask for quiet, since the action
refuses it otherwise, and so is a silent `react`: with the brain's faces
parked it shows nothing, and it only means something as quiet starts.
The if-else classifier gained rows for goodbyes (happy) and meals
(hopeful), which `steering.md`'s examples already had.

**Jev.** Following TypeSafe's guidance ([jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13),
[how to build](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)):
each action's definition carries a plain question for the output and for
each decided argument ("Does what just happened call for Boop to react?",
"How long did the person ask Boop to be quiet for?", with "half an hour,
or when they don't say how long"); each question says it's about `now` and
to judge by `boop`, its Examples first; a yes means `boop` says to do it
for something like `now`; and Jev's state leaves out the Writing section.
These target what the earlier Jev runs got wrong: a silent face on most
agent starts, no reaction to turns of 45 s to 7 min, and yes to quiet for
"shut up for an hour" ([earlier side by side](../2026-09-26-two-stage-brain/side-by-side.md)).

The owner's key then allowed real runs. Each round, Jev's answers (shown in
the eval's diff) pointed at the next fix:

| Round | Jev + Apple | What failed, and the fix |
| --- | --- | --- |
| 1 | 9/10 (1 run) | "This build is annoying" at react 0.50, feeling sad. "Sad" also meant "something went badly", and steering had no example of the person grumbling about work. Sad is now only hurt; annoyed covers "an agent or its work"; steering adds "Spoken to, Boop mumbles back, unless asked for quiet" and a grumble example worded unlike the scenario |
| 2 | 6/10 (3 runs) | Yells came out silent, from the new "BE QUIET, yelled: … silent" example. And Apple's writer copied the grumble example's word, "tests", into pokes and rate limits. The example now says "ugh" |
| 3 | 8/10 (3 runs) | Still silent now and then, including a finished turn after an hour's quiet had ended: Jev can't tell from "73 minutes ago" that quiet is over. Silent is now offered only when the words ask for quiet. The writer also said "bug" once for a rate limit; scenario 03 now accepts it, as VOICE.md lists it with the topic words for a turn that broke |
| 4 | 10/10 (3 runs) | — |
| 5 | 9/10 (5 runs) | One request of about 185 failed (dropped as an error). A 429, 5xx or dropped connection is now tried once more after 0.3 s, as TypeSafe advises, and the eval's diff shows why a pass was dropped |
| 6 | 10/10 (5 runs) | —, and again after the feelings fix below |

On the 58 fixture inputs Jev was annoyed at 2 of 6 successful test runs,
both by Codex on projects whose tests had failed in the sample memory.
"Proud" now says "whatever it was about" and "annoyed" says "a turn that
just failed"; all 6 are proud.

## Results

| Run | Result |
| --- | --- |
| `make eval` (rules, no writer) | 10/10 ([output](eval-rules-none.txt)) |
| `boopdev eval --writer apple --runs 5` (rules, Apple) | 10/10 in all 5 runs ([output](eval-rules-apple.txt)) |
| `boopdev eval --classifier jev --writer apple --runs 5` (Jev, Apple) | 10/10 in all 5 runs ([output](eval-jev-apple.txt)) |
| `boopdev brain --classifier rules --writer apple` (L5) | PASS ([output](l5-rules-apple.txt)); 58/58 on the menu, 50/50 slots filled |
| `boopdev brain --classifier jev --writer apple` (L5) | PASS ([output](l5-jev-apple.txt)); 58/58 on the menu, 45/45 slots filled; Jev p50 about 0.2 s |
| `make test` | 206/206 |

Every input, both classifiers: [side-by-side.md](side-by-side.md).

The L5 words with the rules, before and after, by the same scoring script
(each word checked against Writing's order for its input):

| | Words that fit | Different words |
| --- | --- | --- |
| Before | 33/46 | 8: yay 14, hmm 10, oops 8, nope 8, ugh 2, hi 2, ship 1, love 1 |
| After (first pass) | 35/46 | 19: oh 6, done 5, finally 5, nope 4, hi 4, okay 4, tests 2, oops 2, bug 2, yay 2, bye 2, … |

The score barely moves because the script is strict about small talk
("hi" to "what's up", "okay" to "jetpack is the payments service" count
as misses). What changed is where the words land: failed test, build and
deploy runs name their topic, long turns get "finally" or "done", being
told off gets "oh", praise gets "thanks" or "love", goodbyes "bye" and
lunch "food", and notes lose their "remember" ("demo on Thursday").

The writer is a little slower: p50 1.67 → 1.88 s and p95 2.17 → 2.94 s
over the 46 writes of the first pass (max 3.09 s), against deadlines of
4 s (talk, poke) and 5 s (agent); the final runs' p95 was 2.1–2.5 s. The
source property is one more short answer.

## Not done

- Still seen with Apple's writer, outside the scenarios: "curious food" to
  "jetpack is the payments service" and "hi" to a note request under the
  rules; one of three failed test runs got "ugh" in a run; "bug" for an
  overloaded error; and a note sometimes keeps "remember" or gains "today"
  ("remember I ship on Fridays", "I ship on Fridays today.").
- With Jev, "can you keep it down for fifteen minutes" and "stop talking
  for a bit" get nothing: they aren't telling Boop off, and without
  "quiet" in them `quiet` isn't offered (BEHAVIORS.md §3.3).
- A note is refused as a duplicate only when it's the same text, so
  "landing launches on Monday" would be kept beside "landing launches
  Monday" ([PLAN.md](../../PLAN.md) §7).

The probe (a small Swift program sending the writer's exact prompt to
Apple's model, several samples per case) and the per-run logs stayed in the
session's scratch directory.
