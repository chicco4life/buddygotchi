# Boop: the dashboard

Updated 2026-09-28. `internal/tools/boopctl dash`, a terminal UI (Python
and [Textual](https://textual.textualize.io/)) that shows Boop live: its
state with the device's face, the harness's latest pass, and a timeline
of everything. Its keys force a mood, a reaction or an animation on the
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

Top to bottom:

```
┌ face · live ─────────────────────┐┌ state · DIR ─────────────────────────┐
│ ▀▀▀ the sim's screen, 83×22 ▀▀▀  ││ base, needs you, saying, mood,        │
│                                  ││ sessions, brain, volume, device       │
└──────────────────────────────────┘└───────────────────────────────────────┘
┌ harness · the latest pass ──────────────────────────────────────────────────┐
│ IN   the event, its reflex, the state (collapsed), the questions asked      │
│ OUT  every answer with its probabilities                                    │
│ RAN  each action's ok and message, and whether it's still in progress       │
└─────────────────────────────────────────────────────────────────────────────┘
┌ timeline ───────────────────────────────────────────────────────────────────┐
│ every event, pass, action, settle, device line and status change, following │
└─────────────────────────────────────────────────────────────────────────────┘
 m mood  r react  a animate  p preview  s state  z whole screen  q quit
```

1. **State.** The face (§5), and beside it the facts:
   - `base`: the base state, and how many sessions are busy (the
     `state`'s `busy`), idle (the latest `status`'s sessions) and
     waiting (1 + `attn.more`, or 0 without `attn`)
   - `needs you`: the waiting agent and project, and how many more, or "no"
   - `saying`: the latest mumble's syllables, its word and where it
     falls, its tune and its milliseconds per syllable
   - `mood` (from the latest `state`), with the personality
   - `sessions`: each agent, project and status
   - `brain`: its id, the latest pass's latency, and how many passes were
     dropped
   - `volume`, and whether a `device` is connected
2. **Harness.** The latest pass:
   - **IN:** its event's line and reflex reaction (or "forced by
     dashboard"), the state it sent as one line of section sizes (`s`
     shows it whole), and the questions it asked.
   - **OUT:** the brain and latency, then every answer, its choice and
     every option's probability, most likely first, in the order the
     questions were asked.
   - **RAN:** each action's result, `✓` or `✗`, and its message. A
     started one is `…` and `(in progress)` until its `settle`, then `✓`,
     or `✗` with `(didn't happen: <why>)`.
3. **Timeline.** Every line of `debug.jsonl` as one row with its time,
   following the latest. A `state` resent unchanged (the keepalive,
   [PROTOCOL.md](PROTOCOL.md) §3) is hidden, and a `status` row shows only
   what changed.

Screen text, the bubble's word and the needs-you strip, can't be read at
the face's scale, so it's in the facts instead.

## 3. Where the data comes from

The dashboard reads the state directory's `debug.jsonl` and nothing else:
never `boop.log`, never the `mood` file, and never an action's message
text for its facts. Each line's shape is in
[harness/HARNESS.md](harness/HARNESS.md) §9.

| Line | Shows in |
| --- | --- |
| `questions` | The pickers (§4), so no mood, face or word is written into the dashboard |
| `event` | The timeline, and IN when a pass is for it |
| `pass` | The timeline, the harness pane, and `brain` (latency, dropped) |
| `action` | The timeline (`…` for a started one), and RAN when it's the latest pass's: for the same event (or, forced, for none) and from an action that asks one of the pass's questions, which the `questions` line maps |
| `settle` | The timeline, as `✓ react (16) done` or `✗ react (16) didn't happen: <why>`, and RAN's mark for its action |
| `sent` | The face (§5), `base`, `needs you`, `saying`, `mood`, `volume`, and the timeline |
| `status` | `sessions`, `base`'s idle count, `brain`, `device`, the personality, and the timeline |

**The app starting again.** At each launch the app empties
`debug.jsonl` in place and writes its `questions` line first. So when the
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
| `s` | Shows the latest pass's whole state; a forced pass has none | The same |
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
only the app writes to the board. The facts and the timeline keep showing
the app. Preview is the only way the dashboard forces a look; real looks
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
| Feed | `internal/tools/boopctl_lib/dash/feed.py` | Follows `debug.jsonl`, notices restarts, and keeps what the panes show |
| Face | `internal/tools/boopctl_lib/dash/face.py` | The sim's thread, the 1/3 downsampling and the half blocks |
| Controls | `internal/tools/boopctl_lib/dash/controls.py` | The dev lines, confirming, and Preview's lines |
| App | `internal/tools/boopctl_lib/dash/app.py` | The Textual app: panes, pickers and keys |
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
  had; the counts from `attn` and the sessions; a started action and its
  settles; restarts; the downsampling, and every golden frame's face
  inside the crop; the dev lines built from the `questions` line;
  Preview's lines; and the app's panes and keys through Textual's pilot.
- **Live:** a headless app with the scripted brain, the e2e Claude
  session replayed into it, and the dashboard forcing a mood, a reaction
  and a cheer ([evidence](evidence/2026-09-27-dashboard/README.md)).
