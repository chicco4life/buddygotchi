# Work context: shared pipeline, first implementation

## Implemented

One guide, shared desk snapshot and Voice instance serve scope and existing
remarks. The engine retains bounded first/latest hook intent only in memory,
groups all eligible sessions by canonical project identity, debounces scope,
and rejects obsolete replies. Scope persists on Mac/device without replacing
counts or attention. No per-task model, classifier or new memory writer.

Richer check-result occasions and persisted episodic callbacks are still planned.
The model-facing guide contains their intended behavior, but no absent evidence
is invented to make those sections active.

## Verification

- `make test build`: **361 passed, zero skipped**; Boop and BoopSignal built.
  Offscreen Mac scope snapshots use English companion text with English/Korean UI
  in light/dark appearances.
- `tools/pio_ws.sh run -e ws-amoled164 -e ws-amoled164-usb-debug` from firmware/esp32:
  both variants built. Only the USB-only candidate was temporarily flashed.
- Reserved USB run through `tools/dev/device.py --usb-only`, with immutable
  candidate files and a backup of the device's original firmware/settings.
  `test_work_scope.py` plus `test_agent_dashboard.py`: **18 passed**.
- Two separate complete `tools/shots.py` runs; `golden.py record` on the first,
  `golden.py check --threshold 0` on the second: **49/49 passed at 0.000000 error**.
  All second-capture PNG timestamps are after every first-capture timestamp;
  every pair is also byte-identical. See [capture hashes](capture-sha256.txt).
  Six scope scenes were added; existing 43 golden files stayed identical.
- Exact prior normal firmware/settings restored and normal `usbOnly=false`
  identity verified. See [reservation result](usb-result.json).
- No webcam, normal GUI launch, hook installation, commit or deployment was done.
  The USB-only image is not a release artifact or evidence of production BLE.

Initial verification setup lacked pytest; the wrapper restored the original
firmware after that failure. A second run passed all new scope checks but found
two dashboard tests using stale y=70 pixel masks from the smaller buddy. Those
masks now begin at the specified table band, y=108, with updated label regions;
the final 18-test run passed. The face/table implementation was not changed to
satisfy those old masks.

## Live model: not a quality pass

Synthetic English/Korean inputs were evaluated locally with Foundation Models,
using the same guide and runtime prompt format. No private user text was used.
The [inputs](model-inputs.json), [final sample results](model-results.txt) and
[standalone replay](model-replay.swift) are retained. From the repository root:

```sh
swift plan/evidence/work-context-2026-09-11/model-replay.swift \
  app/Boop/Resources/BEHAVIOR.md \
  plan/evidence/work-context-2026-09-11/model-inputs.json
```

Final samples returned within about 0.9–1.5 seconds, but omitted parts of the
actual scope or copied an unrelated example into Korean output. Earlier trials
also produced incorrect language and timeouts. Shortening the guide and moving
it to the instruction field did not establish reliable semantic behavior.
The replay uses a 30-second overall diagnostic limit; the production Voice path
still has its independently tested five-second deadline.

**Do not treat the fixture text in the screenshots as live model output.** It
proves presentation only. Model coverage, faithful abstraction, appropriate
silence, multilingual quality and privacy adherence remain release gates.
This implementation is a development slice, not a claim that the hero experience
is production-ready. Do not solve this by silently adding a second model stage
or putting semantic grouping rules into the engine.

## Images

- [Mac, English/light](work-scope-en-light.png)
- [Mac, Korean/dark](work-scope-ko-dark.png)
- [Device dashboard, English](scope-dashboard-en.png)
- [Device dashboard, Korean](scope-dashboard-ko.png)
- [Device full face, English](scope-face-en.png)
- [Device idle, Korean](scope-idle-ko.png)

Full local logs/artifacts: `/tmp/boop-work-final-checks.log`,
`/tmp/boop-work-firmware.log`, `/tmp/boop-work-device3/evidence`, and independent
capture directories `/tmp/boop-work-device3/first` and `second`.

## English-only follow-up

Companion scope and remarks now always request English. UI language changes
preserve scope and do not cancel or regenerate display replies; private legacy
reflection keeps its language setting. The guide, draft and specs agree.
The updated suite passed 361 tests with zero skipped. The new regression covers
English model context with Korean UI, and the existing scope regression now
checks that changing UI language preserves the line without another model call.

The English-only local replay used the same `model-replay.swift` and updated
shipped guide with [two English inputs](model-inputs-english.json). It reached
the diagnostic 30-second deadline before returning its first response; see
[output](model-results-english.txt). This is not a model-quality pass. Historical
multilingual results above remain evidence of the earlier guide; multilingual
companion quality is no longer a release gate, but whole-desk coverage and timely
responses remain unresolved. Production still uses its five-second timeout.
No firmware changed or new hardware run was needed for this follow-up. Korean
hardware fixtures continue to verify UTF-8 transport/rendering capability.
