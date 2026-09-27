# Loops and pending: how a reaction ended, and loops

2026-09-27, A14 step 3 ([PLAN.md](../../../PLAN.md)). A brain reaction's
`moment` now goes out with an `id`, and the board answers with `ended`
once none of it plays any more: `done`, `cut` with what cut it, or
`skipped` ([PROTOCOL.md](../../../PROTOCOL.md) §4). The app ends the
reaction's handle from that, and gives up on one whose `ended` hasn't
come by the moment's length plus 3 s
([harness/DECISIONS.md](../../../harness/DECISIONS.md) §5). This replaces
step 2's guess from the app's own timing.

## What ran

| Check | Result |
| --- | --- |
| `make build` | Builds |
| `make -C internal test` | 202 of 202 pass, with the new `testAReactionEndsWhenTheDeviceSaysSo` and `testWhatTheDevicesEndedMeans` (RuntimeTests), and `ended` decoding and the moment's `id` in DeviceLinkTests |
| `make -C internal fw-test` | 110 of 110 pass, with `test_a_waited_moment_says_how_it_ended` (test_behaviour) and `test_a_moment_with_an_id_is_answered_when_it_ends` (test_device) |
| `make -C internal sim` | 11 scenarios, no picture changed |
| tools tests | 26 and 3 pass, run as `make -C internal tools-test` runs them (its venv step can't run in this worktree) |
| `make flash` | Flashed to the board on `/dev/cu.usbserial-110`; `dbg.ping` then said heap 74,068 bytes free, 73,732 at the least |
| L4 by hand (below) | Every way a reaction can end, on the board |
| `make -C internal e2e` | Every checkpoint passes, p95 70 ms from hook to board, and all 8 brain moments got their `ended`. It fails one expectation that has nothing to do with this change (below) |

## L4 by hand

`internal/tools/boopctl bridge --socket /tmp/bl4/usb.sock`, then
`.build/debug/Boop --headless --state-dir /tmp/bl4/state --link usb:/tmp/bl4/usb.sock --socket /tmp/bl4/boop.sock --brain scripted --name Pip --debug`.
Each reaction was forced with `{"dev":"answer","answers":{"react":…}}`
on the hook socket. Then something was done to it: a `dbg.press`
through the bridge, a `{"dev":"moment","anim":"cheer"}`, or a Claude
`PermissionRequest` through `boop-hook` while one reaction played and
another waited its turn. Last, the bridge was killed while a reaction
played.

What the board sent, as a client of the bridge saw it:

```
23:24:30.609 {"t":"ended","id":1,"how":"done"}
23:25:09.763 {"t":"input","k":"tap"}
23:25:09.766 {"t":"ended","id":2,"how":"cut","why":"tap"}
23:25:13.159 {"t":"ended","id":3,"how":"cut","why":"moment"}
23:25:20.947 {"t":"ended","id":4,"how":"cut","why":"needs_you"}
23:25:22.542 {"t":"ended","id":5,"how":"skipped"}
```

What the app printed, abridged to the reactions:

```
23:24:29.131 link brain → {"t":"moment","say":{"syl":"bo lon","tune":"lift","ms":135},"mood":"proud","id":1}
23:24:29.131   … react: Boop made a proud face and mumbled.
23:24:30.609 device: moment 1 ended done
23:24:30.610   ✓ react (2) done
23:25:09.766 device: moment 2 ended cut (tap)
23:25:09.766   ✗ react (5) didn't happen: cut short: you tapped Boop
23:25:13.160 device: moment 3 ended cut (moment)
23:25:13.160   ✗ react (9) didn't happen: cut short: something newer played
23:25:20.947 device: moment 4 ended cut (needs_you)
23:25:20.948   ✗ react (12) didn't happen: cut short: something needed you
23:25:22.532 link brain → {"t":"moment","say":{"syl":"ne-wa ga-ko be","tune":"up","ms":135},"mood":"curious","id":5}
23:25:22.542 device: moment 5 ended skipped
23:25:22.543   ✗ react (14) didn't happen: something needed you
23:25:36.778 link brain → {"t":"moment","say":{"syl":"ya-wa wa-pi di pi-la da","tune":"bounce","ms":115},"mood":"excited","id":6}
23:25:37.203   ✗ react (19) didn't happen: the device disconnected
```

In `debug.jsonl` the first reaction is an action with `"pending":true`
and then, 1.5 s later, a settle `done`, after the board's `ended` line.
[harness/DECISIONS.md](../../../harness/DECISIONS.md) §5 quotes those
lines.

## The pipeline check

`make -C internal e2e` now also checks that the board said how every
brain moment it was sent ended ([VERIFICATION.md](../../../VERIFICATION.md)
L4). All 8 did: 7 `done` and 1 `cut (moment)`. That cut shows why the
app's own timing wasn't enough. The Claude fixture moves the app's clock
40 s mid-turn, so the app sent the next brain mumble while the board was
still playing the last one. The board said the older one was cut short.
Step 2's timing would have called it done.

The run still fails one expectation from before this branch:
`expect.json` wants an event with "claude's deploy failed on", which the
fixture's hooks never produce. Nothing in the core, the adapters or the
fixtures differs from `main`. It's an open item in
[PLAN.md](../../../PLAN.md) §3.

## Step 4: loops

2026-09-28. A `moment` now says how many loops of its design play
(`loops`, 1–6, [PROTOCOL.md](../../../PROTOCOL.md) §3). The rules' cheer
plays enough loops of the mood's task-complete design to last at least
2 s, replacing the fixed 2 s ([BEHAVIORS.md](../../../BEHAVIORS.md) §5).
A reaction's face holds the loops Jev picks with the new `react.loops`
question, once to four times, ending on a loop boundary of the design
showing, and at least as long as its mumble
([harness/DECISIONS.md](../../../harness/DECISIONS.md) §3, §5). facegen
reads each design's loop from its SVG timing and writes it into
`firmware/assets/faces.h` and `app/BoopKit/Core/FaceLoops.swift`, so the
app times a moment as the board plays it.

### What ran

| Check | Result |
| --- | --- |
| `internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check` | 337 frames of 30 scenes match Chrome pixel for pixel; wrote `faces.h` with each scene's `loopMs` and `FaceLoops.swift`. `make -C internal faces` runs the same command, but its venv step can't run in this worktree |
| `make build` | Builds |
| `make -C internal test` | 204 of 204 pass |
| `make -C internal fw-test` | 111 of 111 pass |
| `make -C internal sim` | 11 scenarios, no expectation fails. Two pictures were looked at and accepted: `expression/working-happy-again` (taken after the face's loop now, so the working design is 1.25 s further on) and the new `moments/cheer-second-loop`, which is pixel for pixel `moments/cheer`: the design starts over each loop |
| tools tests | 27 and 3 pass, run as `make -C internal tools-test` runs them |
| `make eval` (once, Jev) | 10/10 scenarios in all 3 runs; median 227 ms, slowest 718 ms. [`eval-debug.jsonl`](eval-debug.jsonl) is every entry; [harness/EXAMPLE.md](../../../harness/EXAMPLE.md) is run 1 of scenario 04 from it |
| `make flash` | Flashed to `/dev/cu.usbserial-110`; afterwards `dbg.ping` said heap 74,068 bytes free, 73,852 at the least |
| On the board by hand (below) | A face held twice ends at the design's second loop boundary; a cheer plays its loops, 6 at most |
| `make -C internal e2e` | Run twice. The first stopped early: a `dbg.state` reply through the bridge never came (the CH340 drops a run of bytes now and then, [VERIFICATION.md](../../../VERIFICATION.md) §2). The second passed every checkpoint, p95 70 ms, and all 7 brain moments sent got their `ended`. It fails only the old deploy expectation (above) |

### Jev's `react.loops`

Across the 105 passes, Jev held a face once for almost everything boop
reacts to: a turn start, a first or third failure, a poke streak, a
failed turn. It picked three times for every comeback (0.88–0.96) and
for a 20-minute finish (about 0.7), and twice for chatter's routine lines
and for a run of 40 s wins. No expectation needed loosening.

### On the board

`boopctl bridge` on `/tmp/bl5/usb.sock`, then
`Boop --headless --state-dir /tmp/bl5/state --link usb:/tmp/bl5/usb.sock --socket /tmp/bl5/boop.sock --brain scripted --name Pip --debug`.
Boop was asleep, whose design loops every 8 s, from the first `state`
at 00:25:07.135.

A forced proud reaction held twice
(`{"dev":"answer","answers":{"react":"proud","react.loops":"twice","word.feeling":"finally"}}`)
went out at 00:25:28.859, 21.7 s into the asleep clock. Its mumble was
over 1.9 s later, but the board said it ended at 00:25:39.144: the
clock's next boundary (+2.3 s) and one more loop (+8 s).

```
00:25:28.859 link brain → {"t":"moment","say":{"syl":"ta-ko ga-da o","word":"finally","at":0,"tune":"lift","ms":135},"mood":"proud","loops":2,"id":1}
00:25:28.859   … react: Boop made a proud face, held twice, and mumbled "…finally!"
00:25:39.145 device: moment 1 ended done
00:25:39.146   ✓ react (2) done
```

A dev cheer went out as `{"t":"moment","anim":"cheer","loops":1}` (the
rule's loops for happy), and an excited reaction held once 0.7 s into
it: that face's loop on the cheer's clock ended at 00:26:02.413, and its
mumble 58 ms later, when the board said it ended (00:26:02.482).

Straight to the board through the bridge, `"loops":3` on a cheer gave
`dbg.state` `"left_ms":7147` (3 × 2.4 s, 53 ms in) and `"loops":9` gave
`"left_ms":14344`: held to 6.

### What the pipeline check showed

Two things that come from the loops, both now open items in
[PLAN.md](../../../PLAN.md) §3:

- After the Claude fixture's rate-limited turn, Boop was idle, whose
  design loops every 9 s, so the scripted brain's reaction, held once,
  lasted 9.0 s. The Codex fixture's first reaction came 4.2 s into it
  and waited its turn.
- Its turn came at 4.84 s, but the moment pump's timer ran 0.3 s late,
  so the schedule dropped it as having waited 5.16 s.

Also, the fixture's 40 s clock jump makes the app give up on a
reaction still on the board ("the device never said it ended"), just
before the board's `ended` arrives and is ignored. Only a moved clock
does that.
