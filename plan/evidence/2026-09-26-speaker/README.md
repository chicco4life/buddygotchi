# Speaker on the bench board

2026-09-26. The owner attached a speaker to the board's 2-pin speaker header
([DEVICE.md](../../DEVICE.md) §3). All runs are over USB with
`tools/boopctl`; the Mac app wasn't connected over Bluetooth (`dbg.ping`
`ble` was `adv`).

## By ear (the owner)

- Mumbles are heard.
- Volume 1 and volume 10 sound clearly different (`boopctl volume`, from the
  Mac-volume thread's A/B script).

## What the board reported

`tools/boopctl voice --count 1` (F5's L2 check), tail:

```
ok  'mm-nu-nn mu'                nap    plan  1020 ms  out  1019 ms  dac  1019 ms  (-0.1%)  amp on
{
  "lines": 16,
  "muted": {
    "amp": false,
    "lines_played": 0,
    "mouth_moved": true
  },
  "ok": true,
  "passed": 16,
  "worst_wall_error_pct": 0.4
}
```

`tools/boopctl mumble`:

```
seed 2175 (--seed 2175 plays these lines again)
ok   happy    'pi-ba-pa li'                          499 ms
ok   happy    'pi-ba-pa li'                  yay     749 ms
ok   excited  'pa-li-pa pi li-pi'                    689 ms
ok   excited  'pa-li-pa pi li-pi'            done    919 ms
ok   proud    'go-ga yo-go gom'                      674 ms
ok   proud    'go-ga yo-go gom'              ship    944 ms
ok   curious  'yu-yu nu ko yo wo pa-gi'              1079 ms
ok   curious  'yu-yu nu ko yo wo pa-gi'      tests   1349 ms
ok   hopeful  'bu-bu nu'                             434 ms
ok   hopeful  'bu-bu nu'                     food    724 ms
ok   annoyed  'ti-pa pe-pi'                          499 ms
ok   annoyed  'ti-pa pe-pi'                  build   749 ms
ok   sad      'yo-o'                                 319 ms
ok   sad      'yo-o'                         oops    640 ms
ok   sleepy   'nu-nu'                                339 ms
ok   sleepy   'nu-nu'                        nap     679 ms
```

`tools/boopctl volume`:

```
round 1 vol  1: played 1349 ms
round 1 vol 10: played 1349 ms
round 2 vol  1: played 1349 ms
round 2 vol 10: played 1349 ms
round 3 vol  1: played 1349 ms
round 3 vol 10: played 1349 ms
round 4 vol  1: played 1349 ms
round 4 vol 10: played 1349 ms
round 5 vol  1: played 1349 ms
round 5 vol 10: played 1349 ms
round 6 vol  1: played 1349 ms
round 6 vol 10: played 1349 ms
```

`tools/boopctl sound jingle`, `sound chirp` and
`moment love --size 2 --say hopeful --word love`:

```
jingle: played
chirp: played
love: playing, 2480 ms, saying 'yo-lun' love
```

`tools/boopctl needs --agent codex --project landing --more 1`, the nudge
ladder ([BEHAVIORS.md](../../BEHAVIORS.md) §3.2):

```
   0.0 s  rung 1  screen needs_you  led #805800  last cue chirp
  45.1 s  rung 2  screen needs_you  led #805800  last cue chirp
 120.1 s  rung 3  screen needs_you  led #FFB000  last cue pulse
cleared: Boop nods and goes back to idle
```

The first `needs` run lost one `dbg.state` reply (the CH340 drop that e2e's
soak retries); the commands now retry a debug request once.
