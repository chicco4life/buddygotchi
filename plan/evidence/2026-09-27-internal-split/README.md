# Production and internal code split

2026-09-27, on `ef142e7`. Everything that doesn't ship moved under
`internal/`, and `Package.swift` moved to the repo root
([internal/README.md](../../../internal/README.md),
[ARCHITECTURE.md](../../ARCHITECTURE.md) §10).

## What ran

| Check | Result |
| --- | --- |
| `make build` from clean | Builds. Its warnings are the ones a clean build of `ef142e7` prints (Runtime.swift, InstallerTests, BoopDev), plus the `ld` "search path not found" warning, which Command Line Tools prints for every linked target, once more for the new `BoopDevKit`. No SwiftPM "unhandled files" or "duplicate rule" warnings |
| `make build` with `import BoopDevKit` added to `app/Boop/main.swift` | Fails: `error: 'Boop-product' is missing a dependency on 'BoopDevKit'`. Without `--explicit-target-dependency-import-check error` the same build only warns and succeeds |
| `make test` | 186 of 186 pass, as on `ef142e7` |
| `make fw-test` | 113 of 113 pass |
| `make fw` | cyd24 builds |
| `make sim` | 10 scenarios, 0 expect failures, 0 new or changed pictures |
| `make tools-test` | boopctl 8 tests and the webcam recorder 3 tests pass; the recorder now builds into `internal/tools/webcam/.build` |
| Doctor in a throwaway HOME (`boopdev hooks install --home "$H"`, then `HOME="$H" internal/skills/doctor/doctor.sh --headless`) | 5 passed, 0 failed |
| `.build/debug/Boop --headless --state-dir /tmp/bh.X`, then SIGINT | Opens its socket, stops cleanly, exit 0 |
| `.build/debug/Boop --snapshots DIR` | 42 PNGs, contrast passes |
| The app's resource bundle | `steering/` only, as before the move; the linked `Info.plist` still carries the Bluetooth usage description and `LSUIElement` |
| Markdown links outside `archived/` and `plan/evidence/` | None broken (an offline check of relative paths and anchors). `archived/` has the same broken links as before the move |

`make eval`, with the key the owner supplied for the run, against
`jev:jev-latest`, reading the scenarios from `internal/app/Evals/scenarios/`:

```
pass  01-short-turn.json  A quick turn is routine  (3/3 runs)
pass  02-long-turn.json  A very long turn that finishes is worth a mumble  (3/3 runs)
pass  03-turn-failed.json  A failed turn is annoying, or a shrug  (3/3 runs)
pass  04-tests-fight-back.json  Tests that keep failing make Boop grumpy, and passing at last makes it proud  (3/3 runs)
pass  05-poke-streak.json  Poked again and again, Boop is annoyed  (3/3 runs)
pass  06-heartbeat-lets-grumpy-go.json  An hour of nothing lets a grumpy mood go  (3/3 runs)
pass  07-chatter-reacts-to-everything.json  The chatter personality reacts to everything  (3/3 runs)
7/7 passed in all 3 runs with jev:jev-latest
latency: median 205 ms, slowest 395 ms (deadline 1250 ms)
```
