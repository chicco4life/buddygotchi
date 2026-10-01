# Overnight pass, second round: the brain

2026-09-27. Phrases, the if-else tables, the harness's debug record and
the evals. Every check below ran on this Mac (macOS 27.0, Apple's model
`apple:27.0`, no Jev key, no device).

## Evals

- `make test`: 242 passed. `make eval`: 45/45, the if-else tables with
  no writer, after every commit.
- `boopdev eval --real --runs 3`: 45/45 in all 3 runs, with Apple's
  writer and normal decided by its table (no key): 585 passes, none
  refused, every one answered on the menu, 387/387 slots filled. The 18
  drops are the replies 14 and 15 expect dropped (quiet mode, something
  needing you). Talk's write p50 1527 ms, p95 2054 ms
  ([eval-real-3runs.txt](eval-real-3runs.txt)).
- The new steps, in every mode and run: "okay, you can talk again" gave
  `quiet ended` and a happy mumble with "yay", and the next turn reached
  the brain; "Hey Pip, remember I always pair on Mondays" kept "always
  pair on Mondays" in About you.
- The scripted wrong-way answers in 14 were dropped by the quiet action
  in every mode and run: quiet(30) for "you can talk again" ("asked to
  stop being quiet") and quiet(0) for "be quiet" ("asked to be quiet,
  not to stop"), 9 each, and the 15 minutes ended on time. Scripted
  steps aren't counted as the brains' passes.

## Writer time for a memory line

`boopdev eval --mode normal --writer apple --only remember --runs 3`:
the 15 writes with a `remember.text` slot took 1583, 1615, 1619, 1671,
1704, 1713, 1715, 1742, 1759, 1799, 1809, 1814, 1866, 1881 and 2202 ms.
With Jev's old half of the deadline, a late Jev left the writer about
1.9 s; with a quarter it has 2.9 s. Jev wasn't run (no key in an agent
shell); its recorded answers take 0.2–0.3 s
([2026-09-26-modes](../../../../archived/evidence/2026-09-26-modes/l5-jev-apple.txt)).
