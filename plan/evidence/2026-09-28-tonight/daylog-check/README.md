# Daylog check: are `boopctl day`'s counts right?

2026-09-28, lane `daylog-check`, an independent check of the
[daylog lane](../daylog/README.md): the counts `boopctl day` prints, the
kept launches' logs, and the commands the docs give.

## What was wrong, and the fix

**The "reacts" column counted the dashboard's reactions as the brain's.**
It counted every `sent` moment with a face, and the dashboard's forced
reactions send those too. In the fixture, 6 of the 20 "brain reactions"
were forced: proud, curious twice, determined, sad and happy. The scripted
brain answered excited every time. The column also mixed two different
things. A reaction that never reached the device (refused, or waited too
long) wasn't in "reacts" but was in "missed", while one sent to no device
was in both.

`boopctl day` now counts the brain's reactions from the `react` action
entries without `by`, started or refused, each in the face its pass's
`react` answer chose. The action entries follow their pass's line, so the
face comes from the last `pass` line before them. Forced reactions and
their misses are counted apart: in the Brain line ("9 forced from the
dashboard, asking for 8 reactions"), and marked `(forced)` in the list of
reactions that didn't happen. So "missed" is now the part of "reacts"
that didn't happen. Cheers and chatter still come from `sent` moments.
HARNESS.md §9's table and VERIFICATION.md §2 say so, and the daylog
README's sample is the new output.

| The fixture | Before | After (counted by hand) |
| --- | --- | --- |
| reacts | 20: excited 14, curious 2, determined, happy, proud, sad | 15, all excited |
| missed | 7 | 2 (02:16 no word it finished, 03:12 no device connected) |
| forced from the dashboard | 9 passes | 9 passes, 8 reactions, 5 of them didn't happen |

## Hand counts

**The fixture** (`internal/tools/boopctl_lib/tests/fixtures/day`, 2
launches). I went through every line except the keepalive states and
counted each column by hand:

- 3 cheers: 01:35:03 (launch 1), 02:08:37 and 05:31:05.
- 17 chatter: 4 in hour 01, 4 in 02, 3 in 04 and 6 in 05.
- 15 of the brain's passes: 4 in launch 1 and 11 in launch 2. 9 forced
  passes: 1 in launch 1 and 8 in launch 2.
- 4 chirps: 01:34:48 (Claude), 01:47:23 (Codex), 01:51:26 (Claude takes
  over, a different agent) and 05:13:59. At 01:47:25 only `more` changed,
  so no chirp: the firmware compares agent and project only
  (`behaviour.cpp`, `onState`).
- Needs-you lasted 12.028 s, 363.666 s and 421.612 s, from the `state`
  that brought `attn` to the first one without it.
- 6 mood changes. The first state after the relaunch is still proud, so
  it's no change: the mood file outlives a launch. The dashboard made 3
  (a forced pass each time), the scripted brain made 3 (for events 1, 35
  and 69), and the dev `mood` line refused one ("already grumpy"), which
  isn't a change.
- 5 taps: one at 01:53 and 3 taps plus a `pokes` at 04:47. The core makes
  one event per tap, and a `pokes` takes the place of the 4th tap's.
- Running 4 h 26 min. The device was connected for all of it except
  02:52:00–03:12:06 (unplugged), so 4 h 06 min.

**A small day, by hand** (`SmallDayTests` in `test_day.py`, new). There
are three launches, as `debug.2.jsonl`, `debug.1.jsonl` and
`debug.jsonl`:

- The first launch ends while something still needs you (30 min, still
  up).
- The second starts disconnected, connects at 10:10, and chirps again for
  the same agent. It should: its first state had no `attn`, so the
  device's didn't either.
- The third starts in a mood set while no debug log ran ("between
  launches").

It also has a Jev mood change, a dashboard mood change without a pass (the
dev `mood` line), a brain reaction that played, one that waited too long,
and a forced reaction refused because something needed you. The hours,
causes, episodes, running time (90 min) and connected time (75 min) were
all worked out before the code ran, and they matched.

**A fresh recording.** I reran `drive_day.py /tmp/bdd` (2 min 28 s, no
`PRIVATE_` marker in either file). Then a separate counter, written apart
from `day.py`, replayed the firmware's chirp rule and tallied the entries.
It agreed with `boopctl day` on every number: 15 passes, 9 forced, 15
brain reactions, 8 forced, 4 chirps, 3 cheers, 19 chatter, needs-you
12.0 s, 363.7 s and 421.6 s, and 6 mood changes. The 1 brain miss and 5
forced misses matched too.

## Kept logs and the dashboard

`relaunch_check.py` (this folder) relaunched `Boop --headless --debug
--link none --brain scripted` 12 times on one state dir. Each launch had
its own project, and the dashboard's own `Follower` (`dash/feed.py`)
followed `debug.jsonl` throughout:

- The Follower saw all 11 relaunches as restarts.
- After each relaunch, `debug.1.jsonl` started with the previous launch's
  lines.
- The number of files stopped growing at 11 (`debug.jsonl` and
  `debug.1.jsonl`–`debug.10.jsonl`). Oldest first, they held projects
  p2 to p12, so launch 1's file was let go.

`boopctl day` then read all 11 launches in order. The only growth left is
within one launch's file, as before.

## The docs' commands, as written

With `HOME=/tmp/bdh`, so that the everyday state dir is a temporary one:

- `make day` on an empty dir exits 1 with "no debug.jsonl in …".
- `make day` on a copy of the fixture prints the summary.
- `make day DATE=2026-09-28` prints the same summary.
- `make day DATE=2026-09-27` exits 1 with "Nothing in the debug logs on
  2026-09-27: …".

These also ran:

- `internal/tools/boopctl day --state-dir internal/tools/boopctl_lib/tests/fixtures/day`
  (the daylog README's command), which prints exactly the sample there.
- `boopctl day --date 2026-09-28 FILE FILE`.
- `boopctl day --help`.
- `python3 plan/evidence/2026-09-28-tonight/daylog/drive_day.py /tmp/bdd`.

## Checked and fine

- **With no brain, events aren't counted as replaced.** With no key the
  core doesn't mark events `wakes_brain` (a headless run with no
  `--brain` had 3 events, all `false`). So "events woke it but got no
  pass" can't read wrong when the brain is off.
- **Only the mood action changes the mood.** It has no decay, so every
  change in a `state` has a `mood` action right after it, or happened
  between launches.
- **A mood action's `state` goes out before its entry,** on the same
  millisecond in both recordings. That's why the 1 s window catches its
  cause.

## Not fixed, noted

- A cheer played from the dashboard (dev `moment`) counts as a rule's
  cheer, since only its `sent` line records it. HARNESS.md §9 now says
  so.
- A board that reboots (USB replugged) chirps again for a needs-you
  already shown. The summary can't see the reboot, so it doesn't count
  that chirp.
- The clock-jump case in PLAN.md §3 depends on timing. The rerun didn't
  reproduce it: the rate-limited turn's reaction played after 2.3 s,
  before the driver's next `advance`. Chatter came to 19 there instead
  of 17 for the same reason.

## Checks that ran

- `make build`: passes.
- `make -C internal test`: 206 of 206.
- `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests`:
  47 pass, 20 of them in `test_day.py`.
- `python3 -m unittest discover -s internal/tools/webcam/tests`: 3 pass.
- `make -C internal fw-test`: 111 of 111.
- `make -C internal sim`: 11 scenarios, 0 expect failures, 0 new or
  changed pictures.
- `relaunch_check.py`: OK.
