# Recorded voice bank: integration evidence

2026-09-29. Boop's voice is now Federico's 40 recorded takes, picked by
meaning and kind in the face's mood (option B in [PLAN.md](PLAN.md),
the owner's choice; decision log in [ARCHITECTURE.md](../../ARCHITECTURE.md)).

## The owner's decisions (2026-09-29)

- Option B: Jev picks a meaning (`say.meaning`) and a kind (`say.kind`);
  Voice maps them onto takes performed in the face's mood.
- When no take fits: silence, with the steering asking Boop to pick a face
  that can say what it means, almost always.
- Swears go on the board and the default personality uses them, at a
  failed turn that stings; the code allows one only on a failure.
- All 40 takes go on the board as they are, none yet approved by ear; the
  six in moods Boop lacks are mapped to the nearest (VOICE.md §3).

## Checks that ran

| Check | Result |
| --- | --- |
| `make build` | Built |
| `make -C internal test` | 309 of 309 passed |
| `make -C internal fw-test` | 159 of 159 passed |
| `make -C internal fw` | Firmware 2,725,867 bytes, 86.7% of app0 |
| `make -C internal sim` | 14 scenarios, 0 expect failures, 0 changed pictures |
| `make -C internal tools-test` | boopctl 67, workday 12, webcam 3: all OK |
| `node internal/boop-design/assets/boop-voice-v1/tools/check.mjs` | Passed |
| `boopdev eval --list` | Every scenario loads, 60–62 included |
| `make flash` over USB, then `boopctl ping` | The board reports voice `01a5f656ec9f`, voice.h's version |
| `boopctl takes` | 39 of 40 on the first run, each take's time at the DAC within 0.1% of its plan; new.d07 was marked "amp OFF" once, and passed alone three times and with all 20 `new.*` takes |
| A forced reaction over USB (`Boop --headless --link usb:…`) | The board played proud's "Mwahaha" and answered `ended` `done` 3.6 s later (harness/DECISIONS.md §5) |
| `make -C internal e2e` (L4) | Passed once in six runs. The failures were all "needs you" reverting to the older state within 8 s: the owner's everyday app (`.build/debug/Boop --debug`) was connected to the board over Bluetooth (`dbg.ping`: `ble: conn`) and resends its own `state` every 10 s. The same revert happens with a plain `state` and no take (a scratch script over USB), so it isn't this change; L4 needs the everyday app off |

## Not yet run

- `make eval` (L5): needs Jev's key. The scenarios changed for the new
  questions, and 60–62 are new.
- `plan/harness/EXAMPLE.md` still shows a Jev pass with the old word
  questions; it needs a real Jev run to replace.
- Listening by ear on the board's speaker, and the approval of each take.
