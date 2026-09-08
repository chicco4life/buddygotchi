# UX: Help

Status: first draft, 2026-09-09, written by the agent; numbers are the
implemented defaults from Phases 1 and 3 and are assumptions to tune.
Refines `VISION.md` §8.

## Nudge ladder (needs you)

| Rung | Default | Behavior |
| --- | --- | --- |
| 0 | On arrival | Amber field, face turns, one "meep?" |
| 1 | 180 s unanswered | One soft repeat, small lean |
| 2 | +300 s, careful stakes only, ≥ 600 s between rung-2 buzzes | Stronger sound, field pulse |
| Focus | Declared | Rung 0 only, silent; careful stakes may still reach rung 2 |

Each dismissal halves the next interval; three dismissals in a row snooze
that tool for the session ("okay, I'll hush about that"). Values live in
`NudgeTiming`.

## Stakes and gloss

Careful: destructive shell, deletes outside the project, force pushes,
pipe-to-shell installs, disk formatting, world-writable chmod, control
characters. Fine: read-only tools. Everything else: check it. Gloss
templates: "runs a command", "deletes files in this folder", "installs
packages", "edits <file>", "reads files", "reaches the internet".

## Stuck

Six attempts on the same goal without a pass, or five minutes of silence
mid-turn. Bubble: "might be going in circles." Clears on the next distinct
progress signal. Tuned quiet: a false stuck is worse than a missed one.

## Spend and rate limits

Rate-limit errors from the agent become uh-oh "hungry" with the third in a
session as a moment ("hungry again (3)"). A forward-looking window meter
needs a source the hooks do not provide today; deferred.

## Come-back call

Any completion leaves the gold orb until collected; the story line shows on
collect. Two completions within 3 s fold into one cheer.

## Recap and teach moments

Recap: Phase 5 voice. Teach moments (one-line explanation of an unfamiliar
tool in the app): Phase 7, opt-out per topic.

## Quick command

Double tap sends the owner's configured prompt to the focused agent session
through the agent's own CLI ("continue" by default). Phase 7 wires it.
