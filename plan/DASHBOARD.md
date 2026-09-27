# Boop: the dashboard

Updated 2026-09-28. `internal/tools/boopctl dash`, a terminal UI (Python
and [Textual](https://textual.textualize.io/)) that shows Boop live the
way its owner thinks of it: **Boop now**, with the device's face, and three
columns side by side: the **mood** (the lasting backdrop), the
**automatic** reactions (reflexes, by rule, at once) and the **decided**
ones (by Jev, a moment later), each with what set it off. The raw timeline
is a key away. Its keys force a mood, a reaction or an animation on the
running app, and Preview shows any look on the dashboard's own copy of
the face. It reads one file, `debug.jsonl`, and writes only to the app's
hook socket. The code is `internal/tools/boopctl_lib/dash/`.

## 1. Running it

The everyday way, with the owner's app and board:

```sh
make debug    # the menu-bar app in debug mode
make dash     # in a second terminal: the dashboard on the everyday app
```

With no board, on a throwaway headless app:

```sh
.build/debug/Boop --headless --state-dir /tmp/bdash --brain scripted --name Pip --debug &
internal/tools/boopctl dash --state-dir /tmp/bdash
```

`--state-dir` is where the app writes `debug.jsonl`; the default is the
everyday app's, `~/Library/Application Support/Boop`, as `boopdev watch`
uses. `--socket` is the app's hook socket, `STATE-DIR/boop.sock` by
default. The app must run with `--debug` for the dashboard to see
anything, since only then does it write `debug.jsonl`. It takes the
dashboard's lines (§4) with `--debug` or headless; plain `make run`
ignores them. `dash` builds `boop-sim` first, as
`boopctl sim` does, so the face is this checkout's firmware.

## 2. Layout

At 150 columns or more, drawn from the tests' fixture
(`dash-columns.jsonl`: the live check's log,
[evidence](evidence/2026-09-28-tonight/dash/README.md), with
probabilities other than 1 and a dropped pass edited in; rows shortened,
and Boop now as it was while the forced reaction played):

```
 No live log: the newest line is from 2026-09-28 08:21:08. Start Boop with make debug.   (only when stale, §3)
┌ face · live ─────────────────────┐┌ Boop now · /tmp/bdash2 ────────────────────────────────────┐
│ ▀▀▀ the sim's screen, 83×22 ▀▀▀  ││ look      idle                                              │
│                                  ││ mood      happy                                             │
│                                  ││ showing   a proud reaction face, three times, “…finally!”   │
│                                  ││ needs you no                                                │
│                                  ││ sessions  0 working, 1 idle, 0 waiting                      │
│                                  ││ board     connected                                         │
│                                  ││ brain     scripted · 0 ms · dropped 1                       │
└──────────────────────────────────┘└─────────────────────────────────────────────────────────────┘
┌ Mood · the lasting backdrop ───┐┌ Automatic · reflexes, by rule ──┐┌ Decided · by Jev, a moment later ─┐
│ happy since 08:13:18           ││ 08:21:05 Boop wiggled on its own.││ 08:21:05 ▸ You poked Boop 4 times │
│                                ││   ▸ You poked Boop 4 times in 3 s││   excited 1.00 · “yay” 1.00 · once │
│ 08:21:05 · mood sat out: You   ││ 08:21:03 Boop wiggled on its own.││   ✓ played                         │
│   poked Boop 4 times in 3 s.   ││   ▸ You tapped Boop.             ││   the mood sat this pass out       │
│ 08:13:18 grumpy → happy        ││ 08:21:02 cheer, loops 1          ││ 08:21:01 forced by dashboard       │
│   ▸ claude started turn 1 on … ││   no event: played from the dash ││   stayed quiet · none 1.00         │
│   scripted: happy 0.87         ││ 08:20:05 cheer, loops 1          ││ 08:20:50 ▸ claude's deploy failed… │
│ 08:13:17 happy → grumpy        ││   ▸ claude finished turn 1 on …  ││   ✗ pass dropped: late: no answer  │
│   forced by dashboard          ││ 08:20:05 working chatter “pa mi” ││     within 1500 ms                 │
│ 08:13:16 happy                 ││   an agent is working            ││ 08:20:09 ▸ claude started turn 2 … │
│   at launch                    ││ 08:13:24 needs you cleared       ││   excited 1.00 · “yay” 1.00 · once │
│                                ││ 08:13:20 needs you: claude ·     ││   ✗ didn't happen: the device      │
│                                ││   jetpack · chirp                ││     never said it ended            │
│                                ││   ▸ claude needs you on "jetpack"││ 08:20:05 ▸ claude finished turn 1… │
│                                ││                                  ││   excited 0.82 · “yay” 0.71 · once │
│                                ││                                  ││   0.64                             │
│                                ││                                  ││   ✓ played                         │
└────────────────────────────────┘└──────────────────────────────────┘└────────────────────────────────────┘
 m mood  r react  a animate  p preview  t timeline  s Jev's state  z whole screen  q quit
```

Narrower than 150 columns the three columns stack, each at most 24 rows
high, and the screen scrolls; narrower than 120, Boop now goes under the
face. `t` shows the raw timeline under the columns, and hides it again.

1. **Boop now.** The face (§5), and beside it one line each:
   - `look`: the base state, and "with the needs-you strip" while
     something needs you
   - `mood`: the latest `state`'s
   - `showing`: what the face is doing now. A decided reaction from its
     start until its `settle`, as "a proud reaction face, three times,
     “…finally!”"; else a reflex for **4 s** after it (`SHOWING_MS`), as
     "cheer, loops 1" or "Boop wiggled on its own."; else "its idle look"
   - `needs you`: the waiting agent and project, and how many more, or "no"
   - `sessions`: how many are working, idle and waiting
   - `board`: connected or not, or "unknown: no live log" while the log
     is stale (§3)
   - `brain`: its id, the latest pass's latency, and how many passes were
     dropped
2. **Mood**, the lasting backdrop. The mood now and since when, then
   every change, newest first: its time, from → to, and what made it: the
   event line of the pass that changed it and the brain's probability for
   the new mood (`scripted: happy 0.87`), "forced by dashboard", or "at
   launch" for the launch's first `state`. A pass for a poke streak asks
   no mood question ([harness/EVENTS.md](harness/EVENTS.md) §6), so it
   shows here as "mood sat out", and a forced mood the app refused as
   `✗ forced mood refused: <why>`.
3. **Automatic**, the reflexes, by rule, at once, newest first, each with
   what set it off:
   - a cheer, with its loops, under the turn end whose event says "Boop
     cheered on its own", or "no event: played from the dashboard"
   - the wiggle the board plays by itself for a tap or a poke streak, under
     the event ("▸ You tapped Boop.")
   - needs you starting or changing, which chirps, under the request's
     event, and clearing
   - working chatter's mumbles, "an agent is working"
4. **Decided**, by Jev, a moment later: every pass that could react,
   newest first. Its event line (or "forced by dashboard"), the face, the
   word and the hold each with its probability (`proud 0.82 · “finally”
   0.71 · three times 0.64`, "no word" when both word questions chose
   none), and its fate:
   - `▶ playing` from the `react` action's start until its `settle`
   - `✓ played`: the settle said `done` (or the action finished at once)
   - `✗ didn't happen: <why>`: the settle's `why`, or a refused action's
     message ("something needs you")
   - `stayed quiet · none 0.64`: the pass chose no reaction
   - `✗ pass dropped: <why>`: the brain didn't answer in time, or
     couldn't be used
   - "the mood sat this pass out", for a poke streak's pass
5. **Timeline** (`t`). Every line of `debug.jsonl` as one row with its
   time, following the latest. A `state` resent unchanged (the keepalive,
   [PROTOCOL.md](PROTOCOL.md) §3) is hidden, and a `status` row shows only
   what changed.

Screen text, the bubble's word and the needs-you strip, can't be read at
the face's scale, so it's in Boop now instead. The columns keep their
newest 400 rows each; the timeline keeps 5000.

## 3. Where the data comes from

The dashboard reads the state directory's `debug.jsonl` and nothing else:
never `boop.log`, never the `mood` file, and never an action's message
text for a fact (a refused action's message is shown as its reason). Each
line's shape is in [harness/HARNESS.md](harness/HARNESS.md) §9.

| Line | Shows in |
| --- | --- |
| `questions` | The pickers (§4), so no mood, face or word is written into the dashboard; and which questions are the mood's, so a pass without them sat the mood out |
| `event` | Mood (the cause of a change), Automatic (what set a reflex off: the event written within **1 s** after the reflex's `sent` line, `TRIGGER_MS`; one with a `reaction` and no `sent` line before it, the tap's wiggle, is a reflex of its own), Decided (the event a pass answered), and the timeline |
| `pass` | Decided (its answers and probabilities, or why it was dropped), Mood (the probability for a new mood; no mood question means it sat out), `brain`, `s`, and the timeline |
| `action` | Decided: a `react` action's fate, for its pass's event (or, forced, the latest forced pass); Mood: a `mood` action names what made the change sent just before it, or was refused; and the timeline |
| `settle` | Decided's `✓ played` or `✗ didn't happen: <why>` for its `react` action, and the timeline |
| `sent` | The face (§5); a `state`: `look`, `mood`, `needs you`, a mood change and a needs-you start, change (a new `attn` `id`, agent or project) or clearing; a `moment` without a `mood`: a cheer, a wiggle or working chatter in Automatic (one with a `mood` is a decided reaction's); `showing`; and the timeline |
| `status` | `sessions`, `brain`, `board`, and the timeline |

**A stale log.** The app writes `debug.jsonl` only with `--debug`, so
with plain `make run` the dashboard would replay an old file and present
it as now. A debug-mode app writes a `sent` line at least every 10 s, the
`state` keepalive ([PROTOCOL.md](PROTOCOL.md) §3), so when the newest
line's `received_at_ms` is more than **15 s** (`STALE_S`) behind the wall
clock, or the file has no lines, a red banner says "No live log: the
newest line is from <time>. Start Boop with make debug.", and `board`
shows "unknown: no live log" instead of the last connection. Checked every
poll, so the banner goes as soon as a line lands.

**The app starting again.** At each launch the app empties
`debug.jsonl` in place, once it has kept a copy as `debug.1.jsonl`
([harness/HARNESS.md](harness/HARNESS.md) §9), and writes its
`questions` line first. So when the
file no longer starts with the first line the dashboard read, the app has
started again: the dashboard reads the file from the top, starts its
panes afresh, and marks the timeline.

## 4. Controls

| Key | Live | In Preview |
| --- | --- | --- |
| `m` | Picks one of the `mood` question's options and sends `{"dev":"mood","mood":…}` | Shows the look in that mood's faces on the dashboard's sim |
| `r` | Picks an answer to each of the `react` action's questions in turn and sends them as a forced pass, `{"dev":"answer","answers":{…}}` | Picks a reaction's face (a mood), how long it holds (`react.loops`' options) and a word or none from the same questions, builds the line with `boopdev voice MOOD [WORD] --json` (the voice Voice gives that mood), and plays it on the dashboard's sim as a `moment` with the face as its `mood` and the hold as its `loops`, as the `react` action sends it: the look shows in that mood's design for those loops, and at least while the mumble plays |
| `a` | Picks `cheer` or `wiggle` and sends `{"dev":"moment","anim":…}` | Plays the same animation on the dashboard's sim |
| `p` | Picks a look (idle, working, asleep or needs you) and enters Preview | Picks another look, or leaves Preview |
| `t` | Shows the raw timeline (§2) under the columns, or hides it | The same |
| `s` | Shows the whole state the brain read for its latest pass; forced passes have none, so they're skipped | The same |
| `z` | Shows the whole screen instead of the face's band (§5), or back | The same |
| `q` | Quits | Quits |

Escape cancels a picker. What each dev line does in the app, and the
rules it keeps, is in [harness/HARNESS.md](harness/HARNESS.md) §9. The app
takes them in debug mode and headless only.

**Confirming.** The socket never replies. The dashboard counts a command
as landed when its entry shows up in `debug.jsonl`: a `pass` by the
dashboard for `answer`, an `action` named `mood` by the dashboard for
`mood`, and a `sent` moment with the same animation for `moment`. When
none arrives within **2 s**, it says so and asks whether Boop is running
with `--debug`. A socket it can't reach is reported at once.

**Preview** stops passing the app's lines to the dashboard's sim and
writes its own: the app's latest `state` with the chosen look (`base`, or
for needs you an `attn` from `claude` on `preview`) and, once `m` picks
one, the mood, sent again every 10 s so the sim never shows the no-app
look; and any animation or reaction. Leaving Preview resets the sim and
replays the latest `state`. Preview never reaches the app or a board;
only the app writes to the board. Boop now, the columns and the timeline
keep showing the app. Preview is the only way the dashboard forces a look; real looks
on the app come from real hooks or `boopdev replay` fixtures.

## 5. The face

**The sim.** The face is `boop-sim` ([VERIFICATION.md](VERIFICATION.md)
L1), run in a thread of its own (`SimFace` in `dash/face.py`). It gets
`{"t":"dbg.clock","run":true}` once, then every `sent` line as it lands,
and a `dbg.shot` about 12 times a second; a frame that hasn't changed
isn't redrawn. When the dashboard starts, and when the app starts again
(§3), the sim gets `dbg.reset`, the clock run again, and only the latest
`state`, never old moments.

**Not in step with the board.** The sim draws this checkout's firmware on
its own clock and blinks on its own random schedule, so a connected board
shows the same looks and moments, but not frame for frame.

**Drawing it.** Half blocks: each character is `▀`, its colour the upper
pixel and its background the lower one. The screen is scaled to exactly
**1/3**, each 3×3 block taking its most common colour, which matches the
face's 3-px grid, so no detail is lost; at 1/4 and 1/6 the window eyes
turn into blobs.

| View | Pixels (end exclusive) | Blocks | Cells |
| --- | --- | --- | --- |
| The face (normal) | x 45–294, y 12–144 | 83×44 | 83×22 |
| The whole screen (`z`) | 320×240 | 107×80 | 107×40 |

The face's band holds everything drawn above the bubble in every golden
frame (`internal/firmware/test/golden`), which `make -C internal
tools-test` checks. The cheer's result card rises onto a tray below the
face, in the bubble's band, so only `z` shows it.

## 6. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Feed | `internal/tools/boopctl_lib/dash/feed.py` | Follows `debug.jsonl`, notices restarts, sorts the lines into Boop now and the three columns, and says when the log is stale |
| Face | `internal/tools/boopctl_lib/dash/face.py` | The sim's thread, the 1/3 downsampling and the half blocks |
| Controls | `internal/tools/boopctl_lib/dash/controls.py` | The dev lines, confirming, and Preview's lines |
| App | `internal/tools/boopctl_lib/dash/app.py` | The Textual app: the banner, Boop now, the columns and the timeline, stacking them when narrow, pickers and keys |
| Shared | `internal/tools/boopctl_lib/common.py` | What the dashboard shares with the rest of `boopctl`: the animations and moods, the Mac's Voice lines through `boopdev voice`, and writing a line to the app's socket |
| The app's side | `app/BoopKit/App/Runtime.swift`, `app/BoopKit/Harness/Harness.swift`, `app/BoopKit/Harness/DebugLog.swift` | The dev lines, the forced pass, and the `questions`, `sent` and `status` lines ([harness/HARNESS.md](harness/HARNESS.md) §9) |

## 7. Checks

- **`make -C internal test`:** the `questions`, `sent` and `status` lines
  and their shapes; a forced pass with no brain that leaves a waiting pass
  alone; a forced mood that changes as Jev's does, device included, and is
  refused when it can't; a forced react refused while something needs
  you; dev lines ignored without `--debug` or `--headless`; and the
  printer's output, a started action's `…` and its settle included.
- **`make -C internal tools-test`**
  (`internal/tools/boopctl_lib/tests/test_dash.py`): the feed against
  `tests/fixtures/headless-debug.jsonl`, recorded from a real headless
  run and since edited to drop the `idle` and `wait` its `state` lines
  had; the three columns against `tests/fixtures/dash-columns.jsonl`,
  recorded from the 2026-09-28 live check and edited as the test says
  (probabilities other than 1, and a dropped pass): mood changes with
  their cause and probability, the poke streak sitting the mood out, each
  reflex and what set it off, and every decided fate (playing, played,
  didn't happen, stayed quiet, dropped); `showing`; the stale-log
  threshold (§3); the counts from `attn` and the sessions; a started
  action and its settles; restarts; the downsampling, and every golden frame's face
  inside the crop; the dev lines built from the `questions` line;
  Preview's lines; and the app's panes, banner and keys through Textual's pilot.
- **Live:** a headless app with the scripted brain and a boop-sim as its
  board over USB, the e2e Claude session replayed into it, taps on the
  sim, and the dashboard forcing a mood, a reaction, a quiet pass and a
  cheer ([evidence](evidence/2026-09-28-tonight/dash/README.md); the first
  version's is [here](evidence/2026-09-27-dashboard/README.md)).
