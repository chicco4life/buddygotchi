# Boop: plan

Updated 2026-09-28. Where Boop stands: each milestone's status (§1), the
checks only the owner can do (§2), the open items (§3) and the later port
to ESP-IDF + LVGL (§4). How each milestone was planned and closed is in
the [v1 build plan](../archived/plan-v1-build/PLAN.md), and the specs are
listed in [README.md](README.md).

## 1. Status

Every v1 milestone is done except A11, which waits on watching the faces
on the board, and apart from what only the owner can check (§2).
[VERIFICATION.md](VERIFICATION.md) defines the checks, and each
milestone's evidence says which ones ran.

| # | Milestone | Status | Evidence |
| --- | --- | --- | --- |
| | The v1 build (M0–J3), the early looks and brains (F5, F6, A6, A7, A9) and the cut to 4 states (C1) | Done or superseded; their rows are in the [archive](../archived/plan-v1-build/status.md) | |
| A5 | Mac app look and flow | Done; the owner still has to check the look (check 17) | [A5](evidence/v1-build/A5/README.md) |
| A8 | Hero moments | Done, as C1 trimmed them; checks 4, 9, 10 and 12 | [evidence](evidence/2026-09-26-hero-moments/README.md) |
| | Overnight pass (2026-09-27): reliability, behaviour and polish across the core, brain, firmware, face, Mac app and tools | Done. The final firmware `cf6d8ae` matches the simulator on the board in all 10 scenarios, `perf --motion` passes and `make -C internal e2e` passes; the new looks still need watching in motion (check 1) | [evidence](evidence/2026-09-27-overnight/) |
| A10 | Jev-only harness: typed events and transcript, a plain-text state, mood and personalities ([harness/](harness/HARNESS.md)) | Done; the evals pass against Jev; checks 12–16 are the owner's | [evidence](evidence/2026-09-27-jev-harness/README.md) |
| | Production and internal code split: what doesn't ship moves to `internal/`, `Package.swift` to the root ([internal/README.md](../internal/README.md)) | Done; the evals pass against Jev, 7/7 in all 3 runs | [evidence](evidence/2026-09-27-internal-split/README.md) |
| A11 | Seven moods, drawn from the mood SVGs: Jev picks the mood, and the device shows each state and reaction in it | In progress. Jev chooses among the moods (six since the follow-up dropped curious) with no minimum time between changes (evals 10/10 in all 3 runs); every `state` carries the mood; the device draws each look and the cheer as the mood's design, exactly as Chrome draws the SVGs. The popover's tile shows the same faces. Still to do: watching it on the board | [moods](evidence/2026-09-27-seven-moods/README.md), [faces](evidence/2026-09-27-mood-faces/README.md) |
| A12 | Live dashboard: `internal/tools/boopctl dash` shows Boop now with its face, and the mood, automatic reactions and decided reactions (with Jev's probabilities) side by side, warns when the log isn't live, and forces a mood, a reaction or an animation ([DASHBOARD.md](DASHBOARD.md)) | Done, headless; check 20 is the owner's | [evidence](evidence/2026-09-27-dashboard/README.md), [redesign](evidence/2026-09-28-tonight/dash/README.md) |
| A13 | Reaction faces: `react` picks one of the moods' faces, and the device draws the look in it while the mumble plays (since A14, for the loops Jev picks) ([harness/DECISIONS.md](harness/DECISIONS.md) §3, [PROTOCOL.md](PROTOCOL.md) §3) | Done in code and the simulator; `make eval` passed 10/10 in all 3 runs; watching it on the board (check 1) is the owner's | [evidence](evidence/2026-09-27-reaction-faces/README.md) |
| A14 | Loops and pending: every animation can loop and whoever plays one says how many times; HISTORY shows what Boop started as in progress until it really ended, and the device says when a moment ended ([harness/HARNESS.md](harness/HARNESS.md) §4–5) | Done, and checked on the board over USB. The harness's started actions (`.started` with a `Pending`, `settle` entries, a ceiling on waiting, and HISTORY's `(in progress)` and `(didn't happen: …)`); `react` is started, and ends when the device says how its moment ended (`ended`: done, cut short and by what, or skipped, [PROTOCOL.md](PROTOCOL.md) §4), or `failed` when dropped, with no device, on a disconnect or when no `ended` comes in time ([harness/DECISIONS.md](harness/DECISIONS.md) §5). Loops: a `moment` says how many loops of its design play (`loops`, [PROTOCOL.md](PROTOCOL.md) §3); the cheer plays enough for 2 s, and a reaction's face holds the loops Jev picks (`react.loops`), from the loop lengths facegen reads from the designs for both sides. Reviewed overnight (2026-09-28), and its eight real problems fixed: a reaction on the board holds the next one until its `ended`, and whatever frees the line sends the next at once; the Mac's schedule follows taps and "needs you"; each launch's moment ids start at a random number; a face cut after its mumble played counts as `done`. `make eval` passes 14/14 in all 3 runs and `make -C internal e2e` passes on the board. "Done, not reviewed" sessions are out of scope | [ended and loops](evidence/2026-09-28-tonight/loops-pending/README.md), [review](evidence/2026-09-28-tonight/review/README.md), [its check](evidence/2026-09-28-tonight/review-check/README.md) |
| | Overnight pass (2026-09-28): the lanes below, merged onto one `main` and checked together, in two rounds | Done. Round 1: the build, 242 Swift tests, 114 firmware tests, the simulator, the tools' tests and facegen pass; the board runs its firmware and passes `make -C internal e2e`; `make eval` passes 14/14 in all 3 runs. Round 2 (hunt2, tune2) on `9146e378`: the build, 258 Swift tests, 114 firmware tests, the simulator and the tools' tests pass; no firmware changed and the board, reserved by the owner, wasn't rerun; `make eval` passed 14/14 in 2 of 3 full runs, and the third lost one pass to the deadline (§3) | [morning report](evidence/2026-09-28-tonight/README.md), [round 2's evals](evidence/2026-09-28-tonight/final/eval-round2.txt) |
| | The core under racing hooks: 38 reports from five race hunters, 34 fixed and 1 in part; a denied subagent's request clears when it ends (`SubagentStop`); each request shown has a number (`attn.id`), so a different one chirps; a fuzz test keeps HISTORY and the screen in step ([ADAPTERS.md](ADAPTERS.md) §4) | Done, headless and on the board's pipeline check; checks 6 and 7 are the owner's; three hook orders need a recording (§3) | [race hunt](evidence/2026-09-28-tonight/core/README.md), [SubagentStop](evidence/2026-09-28-tonight/core-subagentstop/README.md), [check](evidence/2026-09-28-tonight/core-check/README.md) |
| | The second race hunt (hunt2): 22 reports, 17 fixed and 1 in part, and a doc slip. A stop after the safety net ends the open turn; a finish with no turn open is nothing, and a turn Boop joined partway tells the brain nothing; an ended session stays ended for a day; a turn's length leaves out the Mac asleep; request numbers start at random each launch; a reaction keeps its line across a link blip and past a tap; the brain's deadline fires on time and logs Jev's real time; a waiting pass doesn't start under "needs you"; the dashboard's changes sit out a running pass; HISTORY keeps a reaction in progress past the newest 40 ([ARCHITECTURE.md](ARCHITECTURE.md) §11) | Done, headless; each fix's test seen failing without it, by the lane and again by its check. Reports 8 and 12 need a Codex recording, and 21 and the rest of 15 a decision (§3); 16 was decided (5c, below) | [hunt2](evidence/2026-09-28-tonight/hunt2/README.md), [reruns](evidence/2026-09-28-tonight/hunt2/reruns.txt) |
| | Firmware hardening: ASan, UBSan and TSan, a frame-by-frame motion sweep, a 35-minute soak with reactions, `perf --motion`'s rule, and `loops`, `vol` and a mumble's numbers held to their ranges whatever is sent ([DEVICE.md](DEVICE.md) §6) | Done; a short webcam check (L3) passed: the cheer, two held reactions, a tap and four moods' looks | [firmware](evidence/2026-09-28-tonight/firmware/README.md), [check](evidence/2026-09-28-tonight/firmware-check/README.md), [webcam](evidence/2026-09-28-tonight/webcam/review.md) |
| | A day in the logs: debug mode keeps the last 10 launches' `debug.jsonl`, and `boopctl day` (`make day`) sums a day up by the hour ([harness/HARNESS.md](harness/HARNESS.md) §9) | Done | [daylog](evidence/2026-09-28-tonight/daylog/README.md), [check](evidence/2026-09-28-tonight/daylog-check/README.md) |
| | `state` without `idle` and `wait` ([PROTOCOL.md](PROTOCOL.md) §3) | Done | [tidy](evidence/2026-09-28-tonight/tidy/README.md) |
| | Tuned for a working day: the mood changes only for something lasting (16 a day, from 52–53), reactions come with a face that fits, and `workday.py` replays a scripted day ([EVALS.md](EVALS.md) §5) | Done; a first poke streak made Boop grumpy until the follow-up below. A second pass (tune2) made the faces vivid: happy went from 67% to 33–35% of a day's faces, "yay" from 83% to 34–38% of worded reactions, and a quick routine finish gets a face only with something to show, at 0.44–0.52 reactions a finished turn (0.70 before) and still 16 mood changes a day; the owner's second decisions (below) named the last reaction in HISTORY and lowered the bar to 20 s | [tune](evidence/2026-09-28-tonight/tune/README.md), [check](evidence/2026-09-28-tonight/tune-check/README.md), [tune2](evidence/2026-09-28-tonight/tune2/README.md), [its check](evidence/2026-09-28-tonight/tune2-check/README.md) |
| | The owner's follow-up (2026-09-28): a poke streak never changes the mood (its pass asks no mood question), the pass's deadline is 1.5 s, and curious is no longer a mood Jev can pick ([ARCHITECTURE.md](ARCHITECTURE.md) decision log) | Done; `make eval` passed 14/14 in all 3 runs on the rebased branch (13/14 before, `11-comeback-still-showing` 2/3); boop's stopped turn is now a happy "…hmm" | [evidence](evidence/2026-09-28-tonight/followup/README.md) |
| | The owner's second set of decisions (2026-09-28): HISTORY names Boop's last reaction and how long ago (8a); a routine finish gets a face from 20 s, not 40 s (9); the next reaction replaces a face held for its loops once its mumble has played, and the first still ends done (5c) ([ARCHITECTURE.md](ARCHITECTURE.md) decision log) | Done, headless; `make eval` 14/14 in all 3 runs. One scripted day with Jev: 0.75 reactions a finished turn (0.47–0.51 in round 2), happy 44% of faces (33–35%), the same reaction at most 4 times in a row (a small happy face; excited "…tests!" at most twice, from 8). A comeback's repeated "…finally!" is still open (§3). Not on the board: the owner had it | [evidence](evidence/2026-09-28-tonight/decisions2/README.md) |
| P1 | Port to ESP-IDF + LVGL | Later (§4) | |

## 2. Owner checks

What only a person can check: Bluetooth, sound and light, the
real screen and menu bar, and Jev with the owner's key. What Boop should
do is in [BEHAVIORS.md](BEHAVIORS.md) and [UX.md](UX.md). The app runs
the `boop` personality with the owner's Jev key unless a check says
otherwise. Anything
that's off becomes an open item (§3).

**Run so far.** The owner ran checks 1, 2, 3, 4, 5 and 9 on the evening
of 2026-09-27, and noted nothing off. The overnight work of 2026-09-28
came after that run: it changed what checks 6 and 7 expect, and the
faces in 9, 10 and 12, as they now say.

**The board and the app**

1. **Look at the board after the overnight changes.** They were checked
   on it by screenshot (every scenario matches the simulator pixel for
   pixel, [VERIFICATION.md](VERIFICATION.md) L2), but nobody has watched
   them move. Since then the face has become the mood designs (A11): watch
   each look and the cheer in a few moods (`internal/tools/boopctl play
   cheer --mood proud`, for one), the blink at each switch, and the tap's
   sway and heart. Then a reaction (A13): the dashboard's `r` (check 20)
   switches the look to that mood's face for the loops picked (A14), at
   least while the mumble plays, and back; and a cheer's loops
   (`boopctl play cheer --loops 3`). Say what you'd change.
2. **`make run`, or `make debug` to watch everything.** Within about 10 s
   the app connects to `Boop-XXXX` and the board leaves the no-app face.
   `make debug` also prints every hook, decision, device line and brain
   pass as it happens. If Bluetooth won't connect:
   `internal/tools/boopctl bridge`, then
   `.build/debug/Boop --link usb:/tmp/boop-bridge.sock`.
3. **If the agents aren't connected: Settings → Agents → Connect both,
   restart open sessions, then, from inside one agent session, run
   `internal/skills/doctor/doctor.sh`, `echo BOOP_DOCTOR_PING` and
   `internal/skills/doctor/doctor.sh --confirm`.** Both connected, the
   gen-2 `~/.boop` entries gone, and the doctor passes.
4. **Tap the screen lightly, then firmly; press BOOT; hold BOOT; then tap
   four times quickly and keep tapping.** Each touch or press is one
   wiggle, holding BOOT included, and a light touch counts once too
   (`make debug` prints one `device: input tap`), because a touch ends
   only after 50 ms without contact. With Jev's key, the fourth quick tap
   may also get a grumpy face and mumble, and more tapping gets no second grumble
   within a minute ([BEHAVIORS.md](BEHAVIORS.md) §3.3).

**Agents**

5. **Make Claude ask permission for a quick shell command.** Within
   about 1 s Boop leans in with its amber sign, the amber light on the
   board's back glows, the strip says `claude · <project>`, and it chirps
   once. A tap only dips the face. Approving in the terminal blinks it back to working
   once the command has run (a long one stays amber until it ends,
   [ADAPTERS.md](ADAPTERS.md) §4); pressing Esc on the prompt instead
   leaves it amber until it goes idle about a minute later.
6. **Approvals in two sessions.** One chirp, and "+1" in the strip. Answer the
   first and the strip moves to the other, with another chirp, even when
   it's the same agent and project (two worktrees of one repo).
7. **Two Claude subagents at once, one asking permission.** Boop stays
   amber while the other keeps running tools, until you answer. Deny it
   instead, and Boop goes back to working once that subagent ends. This
   needs Claude's new `SubagentStop` hook: the app adds it at its first
   launch since and asks you to restart open sessions
   ([ADAPTERS.md](ADAPTERS.md) §5).
8. **A Codex approval.** Amber about 2 s after Codex asks. One its
   automatic reviewer handles lights up only if the command runs past
   those 2 s, and then stays amber until it ends (§3). This is Boop's
   first real Codex session (§3).
9. **A Claude task that runs past a minute.** The working face (the
   keyboard, in Boop's mood), then a cheer that switches to an excited
   or happy face while its mumble plays, nearly always with "yay"
   ([harness/DECISIONS.md](harness/DECISIONS.md) §2.2).
10. **Ask Claude to run a failing test, then stop.** A determined or
    grumpy face and mumble at the failure ("oops" or "tests"), and maybe
    at the stop. No cheer: Boop goes idle, and back to its mood's face.
11. **Esc while Claude is between tool calls.** Within about a minute Boop
    goes idle, with no cheer; at once if a tool was running.

**Personalities and the brain**

12. **Paste Jev's key in Settings, then work normally for a while.** The
    Personality card loses its "Without a Jev API key, … only cheers,
    wiggles and chatters by rule" line. A routine finish gets a face
    only with something to show: a few minutes' turn an excited "yay",
    a quick one with its checks passing an excited "…tests!", one of
    20 s or more a small happy face with no word, and the rest nothing.
    A stopped turn gets a happy "…hmm". A finish of 10 minutes or more gets an
    excited face and "yay", held three times, on top of the cheer (proud
    if it fought through failures), and Boop turns excited
    ([harness/DECISIONS.md](harness/DECISIONS.md)).
13. **Let tests fail three times in a row, then pass.** On the third
    failure a grumpy face and mumble ("…again!" or "…tests!") and Boop
    turns grumpy (the `mood` file in `~/Library/Application Support/Boop/`);
    when they pass, a proud "…finally!" and Boop turns proud
    ([harness/EXAMPLE.md](harness/EXAMPLE.md)).
14. **`Boop --debug` (`make debug`) through a turn.** The terminal shows
    each event, the pass with Jev's whole state the first time and its
    answers, and what the actions did; `boop.log` has one `brain …` line
    per pass and none of the state ([harness/HARNESS.md](harness/HARNESS.md)
    §9).
15. **Settings → Personality: Chatter for a while, then Boop.** Chatter
    shows a "Chatter" chip, mumbles at nearly everything, including
    routine tool use, and chatters every 30–60 s while agents work. Boop
    is back to speaking up only when something stands out
    ([BEHAVIORS.md](BEHAVIORS.md) §6).
16. **`BOOP_JEV_KEY=… make eval`.** Every scenario passes in all three
    runs ([EVALS.md](EVALS.md)).

**The Mac app and the link**

17. **The popover and the menu-bar icon in light and dark, with an
    approval waiting.** The Warm Terminal look ([UX.md](UX.md) §6), with
    the needs-you icon's deeper amber clear on a light menu bar. In the
    active popover, setup's switches are sage when on and the volume
    slider fills in ink, which `Boop --snapshots` can't show.
18. **Over Bluetooth, an approval arriving as a turn finishes (two
    sessions); separately, BOOT pressed again within a second of letting
    go.** The screen always matches the popover, and the second press is
    heard ([evidence](evidence/2026-09-26-e2e-hardening/README.md)).
19. **Settings → Device → Reconnect; then `kill -9` the app and `make run`
    again; then quit it and wait 30 s.** Both reconnects find the board
    within a couple of seconds, the second by taking over the link macOS
    kept ([PROTOCOL.md](PROTOCOL.md) §2). After quitting, the board shows
    the no-app design with only the unplugged icon.
20. **`make debug`, then `internal/tools/boopctl dash` in another terminal.** The
    dashboard's face shows what the board shows, though not frame for
    frame. `m` grumpy, `r` grumpy with "again", and `a` cheer each land
    (no warning after 2 s), and the board plays the reaction (the look in
    grumpy's design for its loops, at least while the mumble plays) and
    the cheer. The reaction shows in the Decided column as `▶ playing`,
    then `✓ played`, and the cheer in Automatic.
    Then quit and `make run`: within 15 s the dashboard shows the red "No
    live log" banner, and the same keys warn that nothing landed
    ([DASHBOARD.md](DASHBOARD.md) §3–4).

## 3. Open items

Known work that isn't a milestone yet, including drift found and not
fixed. Pick one up by writing it into its spec first.

- **Release.** There's no signing, notarisation, app icon or release
  pipeline yet.
- **The landing page is out of date.** [Its copy](../landing/src/lib/copy.ts)
  describes an older Boop that approved and denied from the device, which
  [VISION.md](VISION.md)'s promises now rule out, and agents v1 doesn't
  watch (Cursor, VS Code). It needs rewriting to match v1.
- **No real Codex session.** Only a Codex `SessionStart` has been
  recorded; the approvals and tool calls in the fixtures are hand-written,
  so the shell tool's name and its argv `command` are guesses. What
  `PostToolUse` reports after a failed command hasn't been seen either, so
  a Codex turn never fails ([ADAPTERS.md](ADAPTERS.md) §3). One recorded
  session with an approval and a failing test run would settle both.
- **Codex's reviewer approving a long command shows "needs you".** Codex
  sends no hook when its automatic reviewer approves, as far as the
  hand-written fixtures know, so a reviewed command that runs past the
  2 s grace shows amber and chirps until it ends
  ([ADAPTERS.md](ADAPTERS.md) §4). The recorded Codex session above
  would show whether there's a signal to wait for
  ([evidence](evidence/2026-09-28-tonight/hunt2/README.md)).
- **A Codex request just after its own `Interrupt` shows for 10
  minutes.** If a `PermissionRequest` lands a few milliseconds after the
  `Interrupt` that stopped its call, no turn is open and the request
  shows amber until the safety net, a new prompt or Esc. Treating it as
  late, like a result, risks hiding a real request, since requests carry
  no `tool_use_id`; the Codex recording above would show whether this
  order happens (report 12,
  [evidence](evidence/2026-09-28-tonight/hunt2/README.md)).
- **An ended session ignores its hooks for a day.** Since hunt2, hooks
  from a session that sent `SessionEnd` are ignored until it sends
  `SessionStart` or a prompt, for `forgetMs`
  ([ADAPTERS.md](ADAPTERS.md) §4). That would hide a real request only if
  an agent asked after its own `SessionEnd` without a `SessionStart`;
  Claude's resume and clear, and Codex's, send one. A recorded session
  that exits with a background subagent still running would confirm it
  ([evidence](evidence/2026-09-28-tonight/hunt2/README.md)).
- **The dashboard's recorded run predates started actions and loops.**
  `internal/tools/boopctl_lib/tests/fixtures/headless-debug.jsonl` has
  `react` lines with no `"pending":true`, no `settle` lines, no
  `react.loops` question, no `loops` on its moments and no `attn.id`;
  `test_dash.py` checks those with lines of its own. The next recording of the fixture
  ([DASHBOARD.md](DASHBOARD.md) §7) brings them in.
- **Some Claude hook orders are guessed, not recorded.** The race hunt
  ([evidence](evidence/2026-09-28-tonight/core/README.md)) left three
  cases open for a recording to settle: whether a message queued
  mid-turn sends `UserPromptSubmit` (if not, a new prompt soon after Esc
  between tools could close the interrupted turn as stopped); what a
  background subagent sends after the main `Stop`, and whether it can
  prompt (today its calls keep the session working for up to an hour);
  and which of two parallel subagents' check results should decide
  whether a turn failed. `SubagentStop` itself hasn't been recorded
  either: its fixture follows Claude's hook reference, and check 7 is
  the first real one.
- **A session's project follows its `cwd` into subfolders.** The project
  is the folder's own name unless it's a worktree
  ([ADAPTERS.md](ADAPTERS.md) §3), so a Claude session that `cd`s into
  `landing/web` becomes `web`. Walking up to the nearest `.git`, cached
  per folder as now, would keep it `landing`.
- **The pipeline check's clock jump cuts one reaction.** The Claude
  fixture moves the app's clock 40 s while a reaction plays, so the app
  stops waiting for its `ended` and the next reaction cuts it:
  `make -C internal e2e` reports one `cut (moment)` it shouldn't
  ([evidence](evidence/2026-09-28-tonight/review/README.md)). Only a
  moved clock does this; moving the jump to while nothing plays would
  end it.
- **Determined has no voice.** Its reactions mumble in the temporary
  default, happy's, while the audio is tuned ([VOICE.md](VOICE.md) §4).
- **Most of Voice's words can't be picked.** The `react` action offers
  11 of the 40 real words (7 exclamations and 4 topics,
  [harness/DECISIONS.md](harness/DECISIONS.md) §3); the rest are recorded
  on the device for nothing until the lists grow.
- **Jev's slow first answers on new steering, at the 1.5 s deadline.**
  After a steering change, Jev's first answers were slow enough to drop
  at the old 1.25 s deadline, working-day runs dropped a few more in
  clusters, and a full `make eval` on the round-2 `main` failed
  `02-long-turn` on a pass dropped at 1255 ms
  ([evidence](evidence/2026-09-28-tonight/final/eval-round2.txt)); the
  earlier 1.28–1.33 s was the deadline's timer, not Jev
  ([evidence](evidence/2026-09-28-tonight/hunt2/README.md)). The deadline
  is now 1.5 s with no warm-up pass (the owner's call, 2026-09-28,
  [harness/HARNESS.md](harness/HARNESS.md) §7). A day's `boop.log` now
  says when Jev answered a pass it was late for
  (`harness: jev:jev-latest answered after N ms, too late for …`), so
  the next working day shows whether 1.5 s is enough.
- **A `Stop` another hook blocks cheers twice.** Claude lets a `Stop`
  hook block the stop, and the agent carries on; its next `Stop`
  carries `stop_hook_active`, which `boop-hook` drops. So one prompt
  cheers at each `Stop` and reads "finished turn 1" twice. Keeping
  `stop_hook_active`, and ending such a turn with no second cheer, would
  fix it; it needs a spec decision
  ([evidence](evidence/2026-09-28-tonight/hunt2/README.md)).
- **A pass already running when "needs you" starts can change the
  mood.** A waiting pass no longer starts under "needs you", but one
  already asking Jev lands and acts: in a hunter's run it changed the
  mood happy → determined 0.55 s into the amber, which redraws the
  needs-you face. Having `mood` sit out while something needs you would
  stop it; it's a behaviour choice (report 15,
  [evidence](evidence/2026-09-28-tonight/hunt2/README.md)).
- **A comeback's finish still repeats the fix's "…finally!".** HISTORY
  now ends with Boop's last reaction and how long ago it was
  ([harness/HARNESS.md](harness/HARNESS.md) §5.3), which ended the runs
  of the same excited "…tests!" (at most 2 in a row in the scripted
  day, from 8). But when a fix's proud "…finally!" is followed 35–55 s
  later by its turn finishing as "a comeback", Jev still makes the same
  proud "…finally!", held three times (both comebacks in one day run),
  since boop.md's Example for a comeback asks for exactly that. Giving
  that Example another word, or telling the guide a comeback right after
  its fix is the same moment, would be the next thing to try
  ([evidence](evidence/2026-09-28-tonight/decisions2/README.md)).
- **Recorded passes still show curious.** [harness/EXAMPLE.md](harness/EXAMPLE.md)'s
  passes and the dashboard tests' `headless-debug.jsonl` fixture were
  recorded with seven moods, so their `mood` and `react` options list
  curious (at 0), and the passes ask `mood` on every event. Re-recording
  them from a new run would bring them up to date.
- **How fast a press shows on the board hasn't been measured since the
  dip.** A press now dips the face 2 px at once, so its first changed
  pixel comes on the press's own ms in the simulator
  (`test_the_redraw_cap_doesnt_delay_a_press`), where the old squish took
  20 ms; the board still has to draw and push it
  ([ARCHITECTURE.md](ARCHITECTURE.md) §9 has the 20 ms budget).
- **Shear during fast moves.** On the webcam the face shears diagonally as
  it moves fast. It's either the panel (no tear-effect sync, and in
  landscape its scan crosses the rows the firmware writes) or the camera's
  rolling shutter. If it shows to the eye, try SPI at 80 MHz (40 now) or
  pushing rows in the panel's order
  ([evidence](evidence/2026-09-26-e2e-hardening/README.md)).
- **USB can lose a line from the board.** The CH340 drops the odd byte
  (two debug replies and 23 characters in a 31-minute soak), and lines
  have no sequence numbers, so a lost tap is gone. Bluetooth doesn't go
  through it. Number the board's lines, or drop to 230400 baud.
- **The cheer's card and tray drop 6 px as each loop starts over.** The
  task-complete designs play once and hold (their tracks are `once`), and
  the device starts the design over at every loop boundary
  ([UX.md](UX.md) §2), so in a cheer of two or more loops the card and
  tray jump back down 6 px in one frame and rise again. The rules' cheer
  is one loop, so only `play cheer --loops`, the dashboard and a moment
  with more loops show it. Designs made to loop, or starting over only
  the gesture, would make it seamless
  ([evidence](evidence/2026-09-28-tonight/firmware/README.md)).
- **About 14 KB of heap headroom.** The minimum free heap, 73.7 KB, is
  only just over the 60 KB target ([DEVICE.md](DEVICE.md) §6), so
  anything that adds RAM needs measuring.
- **A freshly built `boop-hook` is slow once:** about 250 ms on its first
  launch while macOS checks it, then a few milliseconds.
- **`swift build` rebuilds for no reason.** It alternates between a
  no-op (0.4 s) and a 6–9 s rebuild with nothing changed, so build
  timings are noisy until the cause is found.

## 4. P1: Port to ESP-IDF + LVGL (later)

**Gate:** only after the owner has run §2 and confirmed v1 works. Then
port everything, tools and checks included:

- **Project:** ESP-IDF, through PlatformIO (`framework = espidf`) or
  `idf.py`, with `esp_lcd` for the ST7789 and `esp_lcd_touch_xpt2046` on
  separate SPI hosts, as today.
- **Drawing:** LVGL 9 through `esp_lvgl_port`. Boop's canvas renderer
  stays, shown through an LVGL canvas.
- **The rest:** raw NimBLE Nordic UART, the continuous DAC, NVS, and the
  same USB debug channel with `dbg.shot`. `boopctl`, the scenarios, the
  goldens and the webcam checks stay as they are, because the protocol
  doesn't change.

**Done when** the whole L0–L4 suite passes against the ESP-IDF build
unchanged, screenshots match the current goldens or the differences are
reviewed, and performance is the same or better, with the budgets in
[DEVICE.md](DEVICE.md) updated. After P1, Secure Boot v2, flash
encryption and Bluetooth bonding get a milestone of their own.
