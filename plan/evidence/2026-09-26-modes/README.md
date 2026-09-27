# Modes: chatty, normal and calm — 2026-09-26

A9 ([PLAN.md](../../PLAN.md)): three modes set how much Boop reacts and
pick its brain ([BEHAVIORS.md](../../BEHAVIORS.md) §6,
[HARNESS.md](../../harness/HARNESS.md) §6). The new day's reflection went with it.
What you tell Boop to remember goes where it belongs, from meanings spelled
out for both stages: a project or session fact to today's notes, a durable
fact about you to About you, how you like things to Preferences
([HARNESS.md](../../harness/HARNESS.md) §5). Rebased onto `c51c543` (main's
eval-for-real-brains work); everything below ran on the rebased code.

## L0 and the deterministic evals

`make test`: 210 passed, 0 skipped. That includes each if-else table's rows
(`ChattyRulesTests`, `CalmRulesTests`, `PhrasesTests`, with where to
remember), main's input and menu tests, each mode's brains, the core's
cheer and chatter per mode (`CoreModeTests`), a pass keeping the brains it
started with (`HarnessTests`), a new mode taking effect at once in the
runtime (`RuntimeTests`), long-term remembering (`ActionTests`,
`MemoryTests`), and the eval suite with its per-mode character check
(`EvalTests`).

`make eval`: all 12 scenarios in chatty and calm, no writer, 24/24
([report](eval.json)).

**Does it catch regressions?** Each change was made on its own, run, and
undone (before the rebase):

| Change | Result |
| --- | --- |
| Calm cheers every finish | Calm fails the short-turn and mode-switch scenarios |
| `Harness.use` swaps nothing | The mode-switch scenario fails in both modes |

## The evals with real brains

As main's evals ask, each with Apple's model writing and three runs, each
of which must pass:

| Mode | Brains | Result |
| --- | --- | --- |
| Normal | Jev + Apple's model | 11/11 scenarios in all 3 runs ([output](eval-normal-jev-apple.txt)) |
| Chatty and calm | their if-else tables + Apple's model | 22/24 in all 3 runs ([output](eval-chatty-calm-apple.txt)); the two misses are one step of `09-remember` |

The miss: "remember I work with Bob on landing" gets the word "love" about
one run in six, in both modes, where Writing says "okay" to a request. It's
left failing, as an open item.

What getting there found:

- **A steering example gets copied.** With the example "remember I review
  PRs every morning", Apple's model wrote "Reviews PRs every morning." for
  "remember I always review PRs before lunch". The example is now "remember
  I work nights".
- **Taking `none` off a word's list makes the words worse.** Given the
  same prompt, chatty's writer with no `none` in its schema answered a
  failed test run with "ugh" in 4 of 4 runs where calm's wrote "tests" in 4
  of 4. Chatty now asks with `none` allowed, and only a word left empty is
  asked for again without it. On the 54 L5 inputs every mumble got its word
  the first time.
- **Small wording changes near Writing's list move the words.** Two tries
  at hinting "a turn just starting" there each turned calm's "tests" into
  "ugh"; both were undone.
- **Jev is a coin flip on a fact memory already has.** "Remember I ship on
  Fridays" (in the sample memory) got remember 0.43 in one run and 0.53 in
  another: either Jev skips it or the store refuses it. The scenario no
  longer asks; `ActionTests` covers the refusal.

Before the rebase, without main's writer and steering, Jev matched 42 of
43 of normal's decisions after steering was sharpened (it had been 33–35).

## L5

**Jev and Apple's model** (`boopdev brain --mode normal --writer apple`,
[output](l5-jev-apple.txt)): PASS. 0 refused, 54/54 on the menu, 44/44
slots filled, 1 call dropped (a note already there), every kind well inside
its deadline (writer p50 about 1.5 s). Before the rebase, Jev had picked
`quiet` for "shut up for an hour"; main's menus now offer `quiet` only when
the words ask for it.

**Chatty and Apple's model** ([output](l5-chatty-apple.txt)): PASS. **Every
one of the 52 mumbles got a word**, 56/56 slots, writer p50 about 1.5 s.
The words lean on "finally" (11, the very long turns), "hmm" (7) and
"ugh"/"oh" (6 each).

## L4 on the board

`make e2e` ([output](e2e.txt)), the headless app in chatty mode over USB:
PASS. Every checkpoint matched; hook to state on the device p50 50 ms, p95
54 ms; 8 brain moments, none before the rules' reaction or over a rule
moment. Before the rebase, the ordering check had failed on a brain mumble
logged in the same millisecond as the rules' line (chatty's rules answer an
agent start at once); the log is written in order, so the check now counts
a later line in the same millisecond as after.

## The app

`Boop --snapshots` (before the rebase, with the Keychain read stubbed out,
which main has since fixed): Settings in [normal](settings-normal-light.png)
and [chatty](settings-chatty-light.png), and the overview's
[Calm chip](overview-calm-light.png). `skills/doctor/doctor.sh --headless`
in chatty mode: 7 passed, 0 failed.

## Not checked yet

- Switching modes and saving a Jev key in the running menu-bar app: the
  owner's.
