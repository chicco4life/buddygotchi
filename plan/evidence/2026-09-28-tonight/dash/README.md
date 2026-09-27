# The dashboard, redesigned around mood, reflexes and decisions

2026-09-28, branch `ovn6/dash` on local `main` at `68f4cf1f`. What was
built is in [plan/DASHBOARD.md](../../../DASHBOARD.md) §2–4: Boop now with
the face, then three columns side by side (the mood, the automatic
reactions and the decided ones, with Jev's probabilities), the raw
timeline behind `t`, and a red banner when `debug.jsonl` isn't live.

## Screenshots

Textual's `App.save_screenshot`, from the live run below:

| File | What |
| --- | --- |
| [01-wide.svg](01-wide.svg) | 200×62, at the end of the run: the three columns side by side |
| [02-playing.svg](02-playing.svg) | While the forced proud reaction played: `showing` names it, and Decided says `▶ playing` |
| [03-timeline.svg](03-timeline.svg) | `t`: the raw timeline under the columns |
| [04-narrow.svg](04-narrow.svg) | 110 columns: Boop now under the face, and the columns stacked |

## The live run

[`drive.py`](drive.py) (`internal/tools/.venv/bin/python
plan/evidence/2026-09-28-tonight/dash/drive.py`, after `make build`):

1. A headless app, `Boop --headless --state-dir /tmp/bdash2 --link
   usb:/tmp/bdash2/usb.sock --brain scripted --name Pip --debug`, whose
   USB link goes to a second `boop-sim` standing in for the board (no
   real board, serial port or everyday app was used). So reactions end
   with the sim's `ended`, and taps on its screen (`dbg.touch`) reach the
   app as `input` taps.
2. The real dashboard, its own `boop-sim` as the face, under Textual's
   pilot at 200×62.
3. `m` grumpy; the e2e Claude session replayed through `boop-hook`
   (`boopdev replay … --gap-ms 400`); `r` proud, three times, "finally";
   `r` none; `a` cheer; four taps 0.7 s apart, a poke streak.

Every step landed (`ok:` lines, each waiting on its entry in
`debug.jsonl`), and the columns showed, from [debug.jsonl](debug.jsonl):

- **Mood:** happy at launch, happy → grumpy "forced by dashboard", grumpy
  → happy under "▸ claude started turn 1" with the scripted brain's
  `happy 1.00`, and "mood sat out: You poked Boop 4 times in 3 s."
- **Automatic:** needs you with its chirp under "claude needs you", and
  its clearing; the turn end's cheer under its event; working chatter;
  the dashboard's cheer, "no event"; three taps' and the streak's wiggles
  under their events.
- **Decided:** every pass with its face, word and hold at 1.00 (the
  scripted brain), the forced proud reaction `▶ playing` then `✓ played`,
  the forced none "stayed quiet · none 1.00", and the poke streak's pass
  with "the mood sat this pass out".

One pass, for "claude started turn 2", shows `✗ didn't happen: the device
never said it ended`. That comes from the replay: it jumps the headless
app's clock 40 s (`advance_ms`) while the sim board's clock runs in real
time, so the app's ceiling for a started reaction passed before the sim
finished it. It is not a dashboard fault, and the Decided column showed
it as it should.

## The tests' fixture

[`make_fixture.py`](make_fixture.py) turns this run's `debug.jsonl` into
`internal/tools/boopctl_lib/tests/fixtures/dash-columns.jsonl`. The
scripted brain answers everything at probability 1, so it gives the first
pass's mood (`happy 0.87`) and the first turn end's reaction, word and
hold (`excited 0.82 · “yay” 0.71 · once 0.64`) other probabilities, and
makes the pass for the failed deploy a dropped one (`late: no answer
within 1500 ms`), taking out its reaction's action, moment and settle.

## Checks that ran and passed

| Check | Result |
| --- | --- |
| `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests` | 56 tests OK (22 of them the dashboard's, 5 new in `ColumnsTests`) |
| `make build` | Build complete |
| `make -C internal test` | 263 passed, 0 skipped |
| The live run above | Every step landed; the screenshots here |
