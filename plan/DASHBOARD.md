# Boop: the dashboard

Updated 2026-09-27. `internal/tools/boopctl dash`, a terminal UI (Python and
[Textual](https://textual.textualize.io/)) that shows Boop live: its state
with the device's face, the harness's latest pass, and a timeline of
everything. Its keys force a mood, a reaction or an animation on the
running app, and Preview shows any look on the dashboard's own copy of
the face. It reads one file and writes only to the app's hook socket.

## 1. Running it

```sh
make debug                                   # the owner: the menu-bar app in debug mode
internal/tools/boopctl dash                  # in another terminal: the everyday app's state dir and socket

.build/debug/Boop --headless --state-dir DIR --socket /tmp/bdash.sock --debug --brain scripted --name Pip &
internal/tools/boopctl dash --state-dir DIR --socket /tmp/bdash.sock
```

`--state-dir` is where the app writes `debug.jsonl`; the default is the
everyday app's, `~/Library/Application Support/Boop`, as `boopdev watch`
uses. `--socket` is the app's hook socket, `STATE-DIR/boop.sock` by
default. The app must run with `--debug` (or headless) for the dashboard
to see or drive anything; plain `make run` writes no `debug.jsonl` and
ignores the dashboard (§4). `dash` builds `boop-sim` first, as
`boopctl sim` does, so the face is this checkout's firmware.

## 2. Layout

Top to bottom:

```
┌ face · live ─────────────────────┐┌ state · DIR ─────────────────────────┐
│ ▀▀▀ the sim's screen, 83×22 ▀▀▀  ││ base, busy/idle/waiting, needs you    │
│                                  ││ saying, mood, sessions, brain, volume │
└──────────────────────────────────┘└───────────────────────────────────────┘
┌ harness · the latest pass ──────────────────────────────────────────────────┐
│ IN   the event, its reflex, the state (collapsed), the questions asked      │
│ OUT  every answer with its probabilities                                    │
│ RAN  each action's ok and message                                           │
└─────────────────────────────────────────────────────────────────────────────┘
┌ timeline ───────────────────────────────────────────────────────────────────┐
│ every event, pass, action, device line and status change, following on      │
└─────────────────────────────────────────────────────────────────────────────┘
 m mood  r react  a animate  p preview  s state  z whole screen  q quit
```

1. **State.** The face (§5), and beside it the facts:
   - `base`: the base state, and the busy, idle and waiting counts
   - `needs you`: the waiting agent and project, and how many more
   - `saying`: the latest mumble's syllables, its word and where it
     falls, its tune and its milliseconds per syllable
   - `mood` (from the latest `state`), with the personality; `sessions`,
     each agent, project and status
   - `brain`: its id, the latest pass's latency, and how many passes were
     dropped
   - `volume`, and whether a `device` is connected
2. **Harness.** The latest pass:
   - **IN:** its event's line and reflex reaction (or "forced by
     dashboard"), the state it sent as one line of section sizes (`s`
     shows it whole), and the questions it asked.
   - **OUT:** every answer, its choice and every option's probability,
     most likely first, in the order the questions were asked.
   - **RAN:** each action's result, `✓` or `✗`, and its message.
3. **Timeline.** Every line of `debug.jsonl` as one row with its time,
   following the latest. A device `state` resent unchanged apart from its
   `time` (the 10 s keepalive, [PROTOCOL.md](PROTOCOL.md) §3) is hidden,
   and a `status` row shows only what changed.

Screen text, the bubble's word and the needs-you card, can't be read at
the face's scale, so it's in the facts instead.

## 3. Where the data comes from

The dashboard reads the state directory's `debug.jsonl` and nothing else:
never `boop.log`, never the `mood` file, and never an action's message
text for its facts. Each line's shape is in
[harness/HARNESS.md](harness/HARNESS.md) §9.

| Line | Shows in |
| --- | --- |
| `event` | The timeline, and IN when a pass is for it |
| `pass` | The timeline, the harness pane, and `brain` (latency, dropped) |
| `action` | The timeline, and RAN when it's the latest pass's: for the same event (or, forced, for none) and from an action that asks one of the pass's questions, which the `questions` line maps |
| `questions` | The pickers (§4); no mood, feeling or word is written into the dashboard |
| `sent` | The face (§5), `base`, `needs you`, `saying`, `mood`, `volume`, and the timeline |
| `status` | `sessions`, `brain`, `device`, and the timeline |

**The app starting again.** At each launch the app empties
`debug.jsonl` in place and writes its `questions` line first, with that
launch's time. So when the file no longer starts with the first line the
dashboard read, the app has started again: the dashboard reads the file
from the top, starts its panes afresh, and marks the timeline.

## 4. Controls

| Key | Live | In Preview |
| --- | --- | --- |
| `m` | Picks one of the `mood` question's options and sends `{"dev":"mood","mood":…}` | Shows the look in that mood's faces on the dashboard's sim |
| `r` | Picks an answer to each of the `react` action's questions in turn and sends them as a forced pass, `{"dev":"answer","answers":{…}}` | Picks a feeling and a word from the same questions, builds the line with `boopdev voice FEELING [WORD] --json`, and plays it as a `moment` on the dashboard's sim |
| `a` | Sends `{"dev":"moment","anim":…}` for `cheer` or `wiggle` | Plays the same `moment` on the dashboard's sim |
| `p` | Picks a look (idle, working, asleep or needs you) and enters Preview | Picks another look, or leaves Preview |
| `s` | Shows the latest pass's whole state; a forced pass has none | The same |
| `z` | Shows the whole screen instead of the face's band (§5) | The same |
| `q` | Quits | Quits |

What each dev line does in the app, and the rules it keeps, is in
[harness/HARNESS.md](harness/HARNESS.md) §9. The app takes them in debug
mode and headless only.

**Confirming.** The socket never replies. The dashboard counts a command
as landed when its entry shows up in `debug.jsonl`: a `pass` by the
dashboard for `answer`, an `action` named `mood` by the dashboard for
`mood`, and a `sent` moment with the same animation for `moment`. When
none arrives within **2 s**, it says so, and asks whether Boop is running
with `--debug`. A socket it can't reach is reported at once.

**Preview** stops passing the app's lines to the dashboard's sim, and
writes its own instead: the app's latest `state` with the chosen look
(`base`, and for needs you an `attn` from `claude` on `preview`) and,
once `m` picks one, mood, again
every 10 s so the sim never shows the no-app look, and any animation or
mumble. Leaving Preview sends `dbg.reset` and replays the latest `state`.
Preview never reaches the app or a board; only the app writes to the
board. The facts and the timeline keep showing the app.

## 5. The face

**The sim.** The face is `boop-sim` ([VERIFICATION.md](VERIFICATION.md)
L1), run by `Sim` in `internal/tools/boopctl_lib/device.py` in a thread of its own.
It gets `{"t":"dbg.clock","run":true}` once, then every `sent` line as it
lands, and a `dbg.shot` about 12 times a second; a frame that hasn't
changed isn't redrawn. When the dashboard starts, and when the app starts
again (§3), the sim gets `dbg.reset`, the clock run again, and only the
latest `state`, never old moments. The status line the sim prints after
its first protocol line is ignored.

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
frame (`internal/firmware/test/golden`), which `make -C internal tools-test` checks.
The cheer's result card rises onto a tray below the face, in the bubble's
band, so only `z` shows it.

## 6. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Feed | `internal/tools/boopctl_lib/dash/feed.py` | Follows `debug.jsonl`, notices restarts, and keeps what the panes show |
| Face | `internal/tools/boopctl_lib/dash/face.py` | The sim's thread, the 1/3 downsampling and the half blocks |
| Controls | `internal/tools/boopctl_lib/dash/controls.py` | The dev lines, the socket, confirming, and Preview's lines |
| App | `internal/tools/boopctl_lib/dash/app.py` | The Textual app: panes, pickers and keys |
| The app's side | `app/BoopKit/App/Runtime.swift`, `app/BoopKit/Harness/Harness.swift`, `app/BoopKit/Harness/DebugLog.swift` | The dev lines, the forced pass, and the `questions`, `sent` and `status` lines ([harness/HARNESS.md](harness/HARNESS.md) §9) |

## 7. Checks

- **`make -C internal test`:** the three new lines and their shapes; a forced pass
  with no brain that leaves a waiting pass alone; a forced mood that
  changes as Jev's does, device included, and is refused when it can't; a forced react refused
  while something needs you; dev lines ignored without `--debug` or `--headless`; and
  the printer's output unchanged.
- **`make -C internal tools-test`** (`internal/tools/boopctl_lib/tests/test_dash.py`): the
  feed against `tests/fixtures/headless-debug.jsonl`, recorded from a real
  headless run; restarts; the downsampling, and every golden frame's face
  inside the crop; the dev lines built from the `questions` line; and the
  app's panes and keys through Textual's pilot.
- **Live:** a headless app with the scripted brain, the e2e Claude
  session replayed into it, and the dashboard forcing a mood, a reaction
  and a cheer ([evidence](evidence/2026-09-27-dashboard/README.md)).

## 8. Not yet

Stepping frame by frame, picking a timeline row to show its pass,
filters, sharper pictures through the kitty graphics protocol, taps and
talk from the dashboard, and a pin in the core that forces a look (asleep,
working, needs you) on the live app. Looks are forced only in Preview;
real ones come from `boopdev replay` fixtures.
