# Boop v1 build: one iteration

You are one iteration of an unattended loop that builds Boop v1 end to end.
The owner is away. Never ask questions or wait for an answer: decide, note
the decision in `PROGRESS.md`, and keep going. Each iteration starts with a
fresh context, so everything you need is in the repo.

## 1. Orient (about 5 minutes)

1. Read `CLAUDE.md`, then `plan/PLAN.md`: the rules in §3, the status table
   in §4, and §5.
2. Read the last few entries of `plan/evidence/v1-build/PROGRESS.md`, if it
   exists. The last entry says exactly what's next.
3. Run `git status` and `git log --oneline -10`.
   - Be on branch `v1-overnight`. If it doesn't exist yet, M0 creates it.
   - **Uncommitted changes** come from an iteration that was cut off, for
     example by a usage limit. Inspect them, keep what's sound, and carry
     on from there. Don't throw work away without reason.
4. Stop anything a previous iteration left running: `boopctl bridge`,
   headless `Boop` instances, the simulator, serial monitors. Only one thing
   may hold the board's serial port.

If `plan/evidence/v1-build/DONE` exists, there's nothing to do. Stop.

## 2. Work

1. **Pick** the first milestone in PLAN.md §4's order that isn't Passed or
   Blocked. Set it to In progress if it isn't already.
2. **Read** only the specs that milestone needs. The milestone's section in
   PLAN.md links them.
3. **Build** it. No existing code is off-limits: delete anything v1 doesn't
   use (the tag `gen2-final` keeps it), except `landing/` and the specs.
4. **Verify** with the loop in `plan/VERIFICATION.md` and every item under
   the milestone's "Done when". Only mark a check passed if it ran and
   passed.
5. **Commit** whenever tests pass, and at least every 30 minutes, even as
   `WIP <milestone>: <what>`. A usage limit can end this iteration at any
   moment, and uncommitted work is only safe if the next iteration can
   understand it.
6. **Close** the milestone when every check passes:
   - write `plan/evidence/v1-build/<milestone>/README.md`;
   - set the status to Passed;
   - commit `<milestone>: <name> — <one line>`.
7. **When blocked** for about 45 minutes on one problem: write down what
   failed, what you tried and your best guess, set the status to
   `Blocked: <reason>`, commit, and move to the next milestone that doesn't
   depend on it.

Keep the specs true. If the implementation must differ from `plan/`, change
the spec in the same commit and add a row to the decision log
(ARCHITECTURE.md §11).

## 3. End the iteration

End after closing (or blocking) one milestone, or after about an hour of
work, whichever comes first. Before you stop:

1. Append an entry to `plan/evidence/v1-build/PROGRESS.md`: the time, the
   milestone, what changed, which checks ran and their results, and **the
   exact next step**.
2. Commit.

If every milestone except P1 is Passed or Blocked, do J3 instead: the
report, the final firmware flashed and showing the idle face, then create
`plan/evidence/v1-build/DONE` and commit. Never start P1; it waits for the
owner.

## 4. Standing rules

- **Owner's setup:** never modify `~/.claude`, `~/.codex`, `~/.boop` or the
  everyday app's state. Tests use a temporary `HOME` and isolated state
  directories.
- **No Bluetooth from here:** don't launch the app with Bluetooth or run
  `bleak`. Use USB via `boopctl bridge` and `Boop --headless`.
- **Webcam:** authorised for this build run only, under
  `plan/VERIFICATION.md` §6. The owner has positioned the board facing the
  MacBook Air camera. Run the framing check before the first clip of each
  iteration. If framing fails, skip webcam checks and say so.
- **Known traps:** there's no Xcode. SwiftUI's `@State` and Foundation
  Models' `@Generable` macros don't compile here; PLAN.md §1 gives the
  workarounds. SwiftPM cache errors under a sandbox mean you should rerun
  outside it.
- **Permission denials:** auto mode may refuse an action, and nothing
  prompts. Find another way and note it in `PROGRESS.md`.
- **One thing at a time:** work on one milestone, yourself. Don't start
  parallel agents, subagents, background builds of other milestones, or
  extra worktrees.
- **Don't push** unless the owner asks.
