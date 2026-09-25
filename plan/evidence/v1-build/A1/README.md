# A1: App core — adapters, hook client, core rules

Passed on 2026-09-26. This milestone is Mac-only, so the device levels
(L2–L3) don't apply.

## What was built

| Part | Where | What it does |
| --- | --- | --- |
| Hook line | `app/HookWire/` | A new Foundation-only target shared by `boop-hook` and the app. It picks the fields ADAPTERS.md §3 keeps, tags topics (`tests`, `build`, `deploy`, `docs`) from tool input in memory, and sends to the Unix socket with a 50 ms connect timeout |
| Hook client | `app/BoopHook/main.swift` | `boop-hook claude\|codex`: reads up to 256 KB (and drains the rest), writes one line, never prints, and always exits 0. A 1 s watchdog covers a stdin that never closes |
| Adapters | `app/BoopKit/Adapters/` | `Adapter` maps Claude and Codex hooks to the common event, with project names from `cwd` (including git worktrees). `HookServer` is the app's socket server. `Replay` drives recorded payloads through all of it |
| Core | `app/BoopKit/Core/` | A pure state machine: `handle(event)`, `input(…)`, `talk(…)` and `tick(at:)` return effects. It covers sessions, "needs you" (Claude at once, the Codex 2 s grace, clearing, the 10-minute safety net), screen priority and the `state` builder, XP, levels, days, hunger, away, mood, working chatter, quiet and focus, and trigger merging and gates |
| `boopdev replay` | `app/BoopDev/main.swift` | Offline: prints every decision on a virtual clock (`--states` for snapshots only). With `--socket`, it sends payloads through the real `boop-hook` (for J1) |
| Fixtures | `app/Tests/Fixtures/hooks/*/synthetic/` | A Claude permission request with its `Notification`, and two Codex requests: one its reviewer handles within 2 s, and one that waits for a person |

## Checks

| Done when | Result |
| --- | --- |
| L0: mapping and topic tests pass on the recorded fixtures | **Passed.** `make test`: 72/72 ([make-test.txt](make-test.txt)), and three repeat runs were also 72/72. `HookWireTests` runs every recorded payload through the field picking and checks no `PRIVATE_…` text survives. `AdapterTests` covers every Claude and Codex hook in the tables, the Notification types, worktree project names and the recorded sessions in order |
| `boop-hook` exits in under 50 ms when the app isn't running | **Passed**, with one caveat. [hook-timing.txt](hook-timing.txt) has three rounds on the release build. With the socket missing, the slowest of 120 runs took 9.0 ms (p50 4.8 ms). With a stale socket file, the slowest of 60 took 9.1 ms. Every run exited 0 and printed nothing. **Caveat:** the very first launch of a freshly built binary took about 250 ms, twice ([hook-timing-first-after-build.txt](hook-timing-first-after-build.txt)). That's macOS checking a new executable once; it doesn't recur. With the app listening, all 23 fixture lines arrived, with no private text. A 1 MB payload finished within 36 ms |
| Core rule tests for every row of BEHAVIORS.md §3.1–3.2 and §4 | **Passed.** Rows and their tests are below |
| `boopdev replay` on a fixture prints the expected `state` snapshots | **Passed.** `ReplayTests` pins the snapshot sequence for the three synthetic fixtures and checks the recorded Claude session. The outputs are in `replay-*.txt` |

### BEHAVIORS.md rows → tests (`app/Tests/CoreTests.swift`)

| Row | Test |
| --- | --- |
| §3.1 You send a prompt | `testSendingAPromptMakesBaseWorking` |
| §3.1 Finishes under 30 s / 30 s–5 min / 5–20 min / over 20 min | `testTurnUnder30sNods`, `testTurn30sTo5MinCheersSize1`, `testTurn5To20MinCheersSize2`, `testTurnOver20MinCheersSize3` |
| §3.1 Several finish at once | `testSeveralFinishingAtOnceMakeOneCheerAtTheBiggestSize` |
| §3.1 Turn fails | `testFailedTurnPlaysOopsThenSideEye`, `testTopicAndErrorReachTheTriggerLine` |
| §3.2 An agent needs approval | `testClaudeNeedsYouShowsImmediately`, `testCodexWaitsTwoSeconds`, `testCodexRequestHandledByItsReviewerNeverShows`, `testDuplicateWhileWaitingIsIgnored`, `testALateNotificationAfterAQuickApprovalIsIgnored` |
| §3.2 45 s and 2 min rungs | The device runs the ladder (F3: `test_behaviour`, board-verified). The core keeps `attn` steady so the ladder continues |
| §3.2 More than one needs you | `testMoreThanOneShowsTheOldestWithACount` |
| §3.2 You tap Boop | The device nods and hushes the nudges (F3). The core sends no tap trigger while something needs you: `testWhileSomethingNeedsYouOnlyTalkAndReflectionReachTheHarness` |
| §3.2 You answer on the Mac | `testAnyLaterEventClearsIt`, `testApprovingGoesBackToWork` (the device plays the nod when `attn` clears) |
| §3.2 Safety net | `testSafetyNetClearsAfterTenQuietMinutes` |
| §4 Earning | `testOneXPPerFinishedTurnAndFiveForTheFirstActivityOfTheDay` |
| §4 Levels and level-up | `testLevels`, `testLevelUpPlaysAtTheNextCalmMoment` |
| §4 Days together | `testDaysTogether` |
| §4 Hunger table | `testHungerThresholds` |
| §4 Starving loses 1 XP a day, never below the level | `testStarvingLosesOneXPADayButNeverDropsALevel`, `testTheCoreAppliesStarvingAsDaysPass` |
| §4 Never sounds or interrupts | `testHungerNeverSoundsOrInterrupts` |
| §4 First XP after hungry plays `gobble` | `testFirstXPAfterBeingHungryPlaysGobble` |
| §4 Away pauses hunger | `testAwayPausesHunger` |

The tests also cover the §3.3 rows the core owns (tap, push-to-talk, touch
and hold, first activity of the day, reflection), §5 mood, working chatter
timing and topic rate, quiet and focus gates, trigger merging, the snapshot
JSON shape and its 512-byte limit, night and asleep, and stale sessions.

## Found and fixed along the way

- **Eight threads with 15-character project names made a 513-byte `state`
  line**, which the device drops whole. The builder now cuts names to 23
  bytes (the device's field size) and drops thread rows from the end until
  the line fits. PROTOCOL.md §3 says so.
- **A payload over the 256 KB cap is cut off and won't parse.** The hook
  now picks the hook name, session, `cwd` and tool from the start of it.

## Decisions (all in the ARCHITECTURE.md §11 log)

- The new `HookWire` target (PLAN.md §2).
- The core is a pure state machine returning effects (ARCHITECTURE.md §3.2).
- Trigger merging is leading-edge with one held follow-up. Finishes within
  3 s make one cheer, upgraded if a later one is bigger.
- A late `Notification` within 5 s of a clear is ignored. A working session
  silent for an hour counts as idle, and one silent for a day is forgotten
  (ADAPTERS.md §4).
- Days together count the setup day as day 1, and failed turns earn no XP
  (BEHAVIORS.md §4). The Growth line carries `lost: N` while starving
  (ARCHITECTURE.md §4.2).

## Left for later milestones

- Nothing calls the core in a running app yet. A4's headless mode wires
  `HookServer` → `Adapter` → `Core`, sends effects to actions and the device
  link, and ticks once a second.
- `short-term.md`'s Today, Happened and Growth lines come out as effects.
  The A2 memory store writes them.
- There's no recorded Codex session beyond `SessionStart`. The Codex
  fixtures are synthetic, and the tool name `shell` with an argv
  `command` is an assumption. `Topic` also accepts `exec_command` and a
  string `cmd`.
