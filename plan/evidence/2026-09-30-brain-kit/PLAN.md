# Brain kit (piece B): plan and progress

The owner asked (2026-09-30) for the generic multiple-choice harness,
"B", to be written up as a spec and then built, with Boop moved onto it,
without stopping until done. The spec is [plan/kit/BRAIN-KIT.md](../../kit/BRAIN-KIT.md).

## The bar

- Boop keeps working after every commit: `make build`, `make -C internal
  test` and `make -C internal tools-test` pass.
- Boop's prompts stay byte-identical: no Jev key here, so no steering
  eval can check a wording change. `GoldenStateTests` pins every state
  the 60 eval scenarios build, with a scripted brain, before anything
  moves; every step keeps it green.
- Specs change in the same commit as their code.

## Steps

| # | Step | State |
| --- | --- | --- |
| 0 | Golden states: every scenario's states pinned from today's code | Done, 2cad8ddd |
| 1 | The spec, `plan/kit/BRAIN-KIT.md`, with the plan index and the CLAUDE.md table | Done, 58c89b30 |
| 2 | `BrainKit` target: the generic files moved as they are (contracts, brain, Jev, line file); BoopKit re-exports it | Done, 8c7dcdf6 |
| 3 | Open up `Event`: `{seq, at, source, kind, line?, data}`, the log (`Log`, `LogView`) in BrainKit, Boop's typed view of an event, old transcript lines still read; tools read the new lines | Done, 0575fa37 |
| 4 | The kit's harness: inputs and transforms, rules and `did`, outputs and `ended`, `Choice`, the prompt builder, the loop, the tick, with its own tests | Done with 5, f38a766c |
| 5 | Boop on the kit: the view as transforms, the pipeline as rules, mood as a `Choice`, react's `run(now:)`, the runtime, evals, headless and boopdev rewired; specs | Done, f38a766c |
| 6 | Beacon, the second tiny example, in `internal/examples/`, with `beacon` and `kit-emit` | Done |
| 7 | Checks: build, tests, tools tests, headless run with the scripted brain, golden states; the evidence below | Done, 906c446f |

## Decisions made while building

- **Messages are whole sentences.** The kit shows a `did`'s message as
  written, and adds nothing but ` (in progress)`. The brief had HISTORY
  write `<Name> did …` from phrases; that would have reworded Boop's
  lines, which only an interleaved A/B eval with Jev could check.
- **Holds are registered apart** (`h.hold(kind) { … }`), not a `when:`
  argument: with both closures on `input`, Swift's trailing closure
  matched the hold, silently.
- **Held events get a `pass` with `held`**, not a dropped one, so the
  day's summary and the popover's "Jev isn't answering" count only real
  calls.
- **A 0 gives way to any newer event that wakes the brain, answered or
  not.** Counting only the unanswered ones brought the passed-over ones
  back once the newer one was answered (found by `BrainKitTests`).
- **`h.batch`** lets Boop run the core in the same step as the event:
  the core needs the tap's finish, which isn't in the event.
- **The agents' lines use a fold of the log** (`TranscriptView.Fold`)
  that catches up to whatever event it's asked about: a cache of a
  function of the log, since re-folding a session for every event would
  be quadratic.
- **The working heartbeat keeps its own random timer**, reset from the
  log, so its waits, and every eval state, stayed the same.
- **Tap-cut reactions are held by the moment schedule**, which has the
  handle, until the pokes stop.
- **The mood lives in the transcript.** No `mood` file; after 24 hours
  with no change Boop starts calm.
- **The read-back window is the kit's 24 hours**, where it was the last
  two days' files.

## Evidence

All run on 2026-09-30 at 906c446f, on the owner's Mac, with no Jev key
and no board.

- **Commits**, on top of `main` at the time: 2cad8ddd (golden states),
  58c89b30 (the spec), 8c7dcdf6, 0575fa37, f38a766c (steps 1–4, Boop on
  the kit), 67a76046 (Beacon), 906c446f (the sweep), and this one.
- **`make build`**: passes, with its check that nothing shipped imports
  an internal target.
- **`make -C internal test`**: 357 of 357 passed. Among them
  `GoldenStateTests`, whose 387 states from the 60 eval scenarios are
  byte-for-byte those 2cad8ddd recorded before anything moved, 16
  `BrainKitTests` (the kit on its own, the deadline and the socket
  included) and 2 `BeaconTests` (the worked example, as §11 quotes it).
- **`make -C internal tools-test`**: 94 and 3 tests, OK.
- **A scripted working day** (`internal/tools/boopctl workday run
  --state /tmp/bk-day --brain scripted`, seed 1), twice on this branch
  and twice on 2cad8ddd built in a scratch worktree. All four runs
  answered the same 412 events, in the same order, with the same lines
  and the same answers. What differs is the number of working heartbeats
  (14 to 20), which varies from run to run on either side: the headless
  app ticks on real time while the day moves its clock in jumps. The
  branch also writes 2 held passes ("something needs you", a turn on
  `api` while `fix-nav` asked for permission), where 2cad8ddd wrote
  nothing. The first branch run's report is
  [workday-scripted.md](workday-scripted.md): 429 passes, 2 of them
  held, none dropped.
- **A forced pass, headless** (`--link none`): the lines in
  [HARNESS.md](../../harness/HARNESS.md) §9, the pass's event at `seq`
  1, its action at 2 and the action's end at 3.
- **Beacon**: `.build/debug/beacon` prints the worked example (pinned by
  `BeaconTests`). `beacon listen --socket /tmp/bk-beacon.sock`, driven by
  four `kit-emit` calls (two failures, a deploy from `events.json`, a
  pass), is in [beacon-live.txt](beacon-live.txt).

Not checked here: anything with Jev (no key, so no steering eval; the
prompts are pinned byte-for-byte instead), the board over USB or
Bluetooth, and a Linux build of `BrainKit`.

## Rebased onto main-refactor

The owner asked (2026-09-30) for the branch to go on top of
`main-refactor` (a6d5447d, agent-hooks). The commits above are now
47763219 (golden states), 2b4d462b (the spec), dd67bdd5, 0fea574f,
c94f20af (steps 1–4), a8366d11 (Beacon), a651c5e4 (the sweep) and
35ac9f7b (the evidence). The one real conflict was the session
bookkeeping, now agent-hooks' `SessionFold` on `AgentEvent`: Boop's
changes to it were dropped, and `AgentEvent(Event)` reads the kit's
event shape. Every commit was built and its Swift tests run during the
rebase. At the tip, before the review fixes: `make -C internal test`
passed 302 of 302 (the hook tests moved to agent-hooks, whose own 76
passed), with the 387 golden states unchanged, and
`make -C internal tools-test` passed 94 and 3.

## Review (2026-09-30), ended early

Four reviewers read the branch: the kit's code, Boop's move onto it,
the specs, and the tests, Beacon and the tools. The owner asked to stop
before all the findings were fixed; the one on Boop's move was stopped
before it reported.

Fixed in the review commit (302 of 302 Swift tests, golden states
unchanged):

- A double past about 1e±127 in an event crashed the app when it was
  written; it's now written as a plain double.
- An event given an earlier `at` than the last could lose events at the
  next launch and hide a waiting one; one with a future `at` emptied the
  memory. `at` now never goes back, nor past the clock.
- The log let go of old events only once they were an hour past
  `keepMs`, so a running app and a relaunched one could see different
  things for events 24–25 hours old. It now trims on every event and
  tick.
- The kit pruned old files only at launch, and a launch after more than
  14 idle days restarted `seq` at 1. It now prunes on the first event of
  a new day too, and reads `seq` before pruning.
- A view's `dids(for:)`, `ended` and `answered` ignored a transform's
  cut, and `events(after:)` trapped for a `seq` past it.
- `h.hold` on a kind with no input gave that kind a line.
- The stale events noted grew without end.
- `JevBrain` reported no probability at all, not 1, for a pick given
  without probabilities.
- `EventServer` could never be let go of, read one connection at a
  time, and lost lines a long connection sent after a pause. Each
  connection is now its own, and each line is handed on as it ends.
- `kit-emit` turned `007` into 7 and `+4` into 4, and printed its help
  when `--line`'s text was `-h`.
- The spec said the kit refuses answers that leave a question out; only
  `JevBrain` does, and Boop's scripted test brains rely on answering
  some. §8 now says so.

Still open:

- **Kit:** duplicate question keys crash at the first call, where §5.1
  says the kit refuses to start; a relaunch within 10 s can answer an
  event from before it, which §9 says never happens; `onLine` isn't
  called for events read back at launch; `changedDuringPass` is state
  kept outside the log; `history()` and `all(since:)` scan the whole
  day.
- **Tests:** nothing pins `maxWaitMs` (10 s), the kit's `keptDays` and
  `keepMs` defaults, react's 90 s `openFor`, a late answer running no
  output, the older-line branches of `Event.legacy`, or a pass going
  stale when the brain changes mid-call. The deadline test measures
  `respond`'s sleep, not the loop's timer. `GoldenStateTests` passes
  green while re-recording with `BOOP_GOLDEN_RECORD=1`. The fixes above
  have no tests of their own yet.
- **Tools:** the dashboard shows 0 ms for Jev after a held pass, and
  `workday` counts held passes as passes.
- **Beacon:** `reachBack` keeps reaching back to the last red streak
  after the build is green, not only when the pass is NOW.
- **Docs:** BRAIN-KIT §3.1's example interpolates a `JSONValue`
  (`string("main")`); EVENTS.md §1 still says passes are in
  `debug.jsonl` only; §7.1 says to set `reading` to nil (it's an enum);
  `.failed` carries no facts; the §2.1 and §2.2 example lines, EVENTS.md's
  `did`/`ended` example and DECISIONS.md §5's "recorded" lines weren't
  taken from a run; EXAMPLE.md still says `mood` saved the mood;
  plan/README.md's HARNESS and EVENTS rows are out of date; a ViewTests
  comment says two days' files; CLAUDE.md's `make build` line leaves out
  `beacon` and `kit-emit`; this file's step numbers differ from §14's;
  EVENTS.md says a raw tool wait gets a line; BRAIN-KIT never names
  `resume()`, `use(_:)`, `respond(to:)`, `Options.loop` or `idle`; §13
  cites EVENTS.md §1 for the shape (it's §2); §7.2 leaves out that older
  in-progress events come only from inside the time window.
