# Loops and pending: the device says when a reaction ended

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
