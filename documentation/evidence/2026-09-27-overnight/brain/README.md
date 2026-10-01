# Overnight pass: the brain lane

2026-09-27. Classifiers, writer, harness, actions, evals and voice. Every
check below ran on this Mac (macOS 27.0, Apple's model `apple:27.0`, no
Jev key, no device).

## Evals

- `make eval` / `boopdev eval`: all 15 scenarios in all three modes with
  the if-else tables and no writer, 45/45
  ([eval-rules-every-mode.txt](eval-rules-every-mode.txt)). Normal is
  now deterministic too (`NormalRules`), and 13, 14 and 15 are new.
- `boopdev eval --mode chatty|normal|calm --writer apple --runs 3`: 15/15
  in all 3 runs in every mode, with greedy sampling
  ([chatty](eval-apple-chatty-3runs.txt), [normal](eval-apple-normal-3runs.txt),
  [calm](eval-apple-calm-3runs.txt)). Wall time 250 s, 147 s and 79 s.
- Jev was not run (no key in an agent shell). Its fallback to normal's
  table is covered by `JevClassifierTests.testNormalsTableDecidesWhenJevCant`.

## Writer latency

[writer-latency.txt](writer-latency.txt): `boopdev brain --mode chatty
--writer apple` over the 54 recorded inputs, with a full day's short-term
memory ([full-short-term.md](full-short-term.md), 38 Happened lines).
Keeping only the last 5 Happened lines took the write p50 from 2166 to
1567 ms for a finished turn and from 2161 to 1648 ms for talk. With the
fixture memory (5 lines) it was about 1.5 s either way.

Also tried and dropped: leaving steering's What Boop can do and
Remembering out of the writer's instructions. Memory lines got worse
("quiet before 10am" copied from long-term, "today" as a line) and
requests to remember got "hi".

## Words under greedy sampling

Greedy makes each run the same, but the words are sensitive to any
change in the prompt. A failed test turn flipped between "tests" and
"ugh" (with the source, "the failed topic", right both times) as
unrelated lines of steering changed; 06 and 13 accept both. A request to
remember got "love" until Writing put "okay to 'remember' or any
request" first. PLAN.md §7 tracks the tests/ugh edge.

## Voice

Same output by construction, checked by hashing 48,000 lines across
every feeling and two dialects, and the `--why` rejects, before and after:
identical. `boopdev voice happy yay --count 1` went from 0.17 s to 0.10 s
and `--count 20000` from 9.3 s to 3.7 s (debug build). The English word
list keeps 20,035 of its 234,291 words: only those spelled with the
letters of Boop's syllables can match gibberish.
