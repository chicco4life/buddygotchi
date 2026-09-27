# The live dashboard: `internal/tools/boopctl dash`

2026-09-27, on branch `live-dashboard`, rebased onto `main` at `a17fea3e` (after the `internal/` split, push-to-talk and quiet mode removed, and the seven moods with their faces); every check below ran on that. What was
built is in [plan/DASHBOARD.md](../../DASHBOARD.md); the app's side (the
`questions`, `sent` and `status` lines, and the dev lines) is in
[harness/HARNESS.md](../../harness/HARNESS.md) §9.

## What ran, and passed

| Check | Result |
| --- | --- |
| `make test` | 195 passed, 0 skipped. New: the three debug lines and their shapes, a forced pass with no brain, one that leaves a running and a waiting pass alone, a forced mood that changes as Jev's does (the device hears it) and is refused when it can't, a forced react refused while something needs you, dev lines ignored without `--debug` or `--headless`, and the printer's output pinned |
| `make tools-test` | 26 `boopctl` tests (17 of them the dashboard's, `internal/tools/boopctl_lib/tests/test_dash.py`) and 3 webcam tests, OK |
| Live, headless (below) | Every step landed; screenshots here |
| Live, a real terminal | `internal/tools/boopctl dash` in a pseudo-terminal (170×60) on a headless app: it built the sim, drew the face in half blocks, `m` → grumpy and `a` → cheer each showed "landed" and reached `debug.jsonl`, and `q` exited 0 |

The dashboard's tests read `internal/tools/boopctl_lib/tests/fixtures/headless-debug.jsonl`,
recorded from a real run of the same headless app: the e2e Claude session,
then a forced mood, a forced pass, `cheer` and `wiggle`, another turn (whose Jev pass changes the mood back to happy), and a
forced react while something needed you ("something needs
you"). No `PRIVATE_` marker is in it.

## The live check

```sh
.build/debug/Boop --headless --state-dir SCRATCH/bd --socket /tmp/bdash.sock --debug --brain scripted --name Pip &
.build/debug/boopdev replay internal/app/Tests/Fixtures/hooks/e2e/claude/session.jsonl --socket /tmp/bdash.sock --gap-ms 400
internal/tools/boopctl dash --state-dir SCRATCH/bd --socket /tmp/bdash.sock
```

[`drive.py`](drive.py) runs exactly that, with the dashboard under
Textual's headless driver (`App.run_test`), the real `boop-sim` as its
face, and the keys pressed by Textual's pilot; it saves each SVG with
`App.save_screenshot` and the sim's screen beside it as a PNG
(`internal/tools/.venv/bin/python plan/evidence/2026-09-27-dashboard/drive.py SCRATCH`).

The timeline showed the session's five events, as expected:

```
▸ 1 turn_start: claude started turn 1 on "jetpack".
▸ 4 needs_you (no pass): claude needs you on "jetpack".
▸ 5 turn_end: claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. Tests passing.  [Boop cheered on its own.]
▸ 8 turn_start: claude started turn 2 on "jetpack", right after its last one.
▸ 11 turn_end: claude finished turn 2 on "jetpack": failed (rate limit) after 40 s, a long turn, 0 tools.
```

Every pass was the scripted brain's excited "…yay!". Then the keys, each
confirmed by its entry in `debug.jsonl`:

| Step | Entry | Face |
| --- | --- | --- |
| `m` grumpy | `{"action":{"by":"dashboard","for":null,"latency_ms":2,"message":"Boop's mood changed: happy → grumpy.","name":"mood","ok":true},…}`, and a `state` with `"mood":"grumpy"` | The grumpy faces: slanted lids and a flat frown ([03-mood-sim.png](03-mood-sim.png)) |
| `r` annoyed, again, no topic | A `pass` `"by":"dashboard","for":null` with each answer at `p` 1, then `✓ react: Boop mumbled, annoyed: "…again!"` | The mouth moving through the mumble ([04-react-sim.png](04-react-sim.png)) |
| `a` cheer | `{"sent":{"t":"moment","anim":"cheer","ttl":5},…}` | Grumpy's cheer: a small escaped smile, and the result card on its tray below the face ([05-cheer-sim.png](05-cheer-sim.png)), which the face's crop leaves out and `z` shows |
| `p` needs you | Nothing: Preview writes only to the dashboard's sim | The needs-you card ([07-preview-needs-you-sim.png](07-preview-needs-you-sim.png)) |

The app logged `dev: mood grumpy`, `dev: forced pass → react` and
`dev: moment cheer` in `boop.log`. In the recording run, the next Jev
pass read the forced results in HISTORY as Boop's own, under the event
before them, with MOOD grumpy and no "dashboard" anywhere in the state:

```
just now: claude finished turn 2 on "jetpack": failed (rate limit) after 40 s, a long turn, 0 tools.
  Boop mumbled, excited: "…yay!"
  Boop's mood changed: happy → grumpy.
  Boop mumbled, annoyed: "…again!"
```

## The screenshots

| File | Shows |
| --- | --- |
| [01-session.svg](01-session.svg) | After the session: the face during the last mumble ("…yay!"), the facts, the last Jev pass, the timeline |
| [02-state.svg](02-state.svg) | `s`: the state Jev read, whole |
| [03-mood.svg](03-mood.svg) | After `m` grumpy |
| [04-react.svg](04-react.svg) | After the forced pass: IN "forced by dashboard", OUT at 1.00, RAN ✓ |
| [05-cheer.svg](05-cheer.svg) | After `a` cheer |
| [06-whole-screen.svg](06-whole-screen.svg) | `z`: the whole screen at 107×40 |
| [07-preview-needs-you.svg](07-preview-needs-you.svg) | `p` needs you: Preview's face |
| `NN-*-sim.png` | The sim's own screen at the same moment, 320×240 |

SVG renderers leave hairlines between rows of `▀`; a terminal doesn't.

## Not checked here

- **`make debug` on the menu-bar app.** Its dev lines are on under
  `--debug` (`MenuBarApp.swift`), but the menu-bar app uses Bluetooth, so
  only the owner can run it: [PLAN.md](../../PLAN.md) check 21.
- **A board.** No board was on USB; the face is the sim's.
- **Jev.** Only the scripted brain ran; the dashboard reads Jev's passes
  the same way, since they share the `pass` line.

## Notes

- The worktree's `internal/tools/.venv` comes from `make tools`, which
  installs Textual from `internal/tools/requirements.txt`.
