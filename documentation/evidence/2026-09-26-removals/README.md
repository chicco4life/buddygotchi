# Focus mode, touch-and-hold and stretch/yawn removed — 2026-09-26

The owner removed three features to simplify Boop before its brain is split
in two (PLAN.md A7):

- **Focus mode:** the core's `focus`, the `focus` field in `state`, the
  device's hold-to-toggle on the status strip, its focus icon and every
  focus check (chirps, rung-3 pulses, mumbles, jingle), and the Settings
  toggle and Modes reminder.
- **Touch and hold on the face** (`input` `feel`): the device's mood face
  and the core's mumble for it. A long touch now counts as a tap when you
  let go, on the face or the strip. The Mac ignores `focus` and `feel` from
  an older board, and the device ignores `focus` from an older Mac.
- **The first activity of the day's `stretch` → `yawn` and its +5 XP.** The
  animations are gone from the device too. The day boundary stays: it
  starts reflection.

## Checks

| Check | Result |
| --- | --- |
| L0 Swift (`make test`) | 199 passed. Two tests went with the features (touch-and-hold, the focus toggle); new ones pin that a new day is quiet and earns nothing, and that an old board's `focus` and `feel` are ignored. Without the 15-byte `focus` field, all eight status-strip rows now fit in a 512-byte `state` |
| L0 firmware (`make fw-test`) | 100 passed. New: a long touch is a tap on release, also during needs-you; a `state` with `"focus":true` sounds and looks exactly like one without; `stretch` and `yawn` are unknown names |
| `make fw` | Builds (RAM 14.0%, flash 55.7%) |
| L1 (`tools/boopctl sim`) | 11 scenarios, 0 expect failures. Goldens looked at and updated, below |
| L2 (the board over USB) | **Not run.** The board was on USB, but the owner's everyday app was running and connected to it over Bluetooth, so a flash would have cut it off and its `state` would have overwritten the test's (VERIFICATION.md L2, one writer) |
| L4 (`make e2e`) | **Not run**, for the same reason. Its expectations changed: `app/Tests/Fixtures/hooks/e2e/expect.json` XP 8 → 3, without the first activity's +5 |

## Goldens

Changed, each with only the focus icon's 15×15 box (x 271–285, y 215–229)
now black; looked at against the old picture, nothing else moved:

- `layout/needs-you-long.png`, `layout/stats-long-name.png`,
  `layout/threads-eight-agents.png`, `screens/strip-icons.png`: focus mode
  removed, so the target icon left of the quiet and mute icons is gone.

Deleted with their scenario steps:

- `behaviour/feel-happy.png`, `behaviour/feel-tired.png`: touch-and-hold removed.
- `behaviour/focus-on.png`: focus mode removed.
- `moments/stretch.png`, `moments/yawn.png`: the animations removed. Later
  steps in `moments.jsonl` moved 20 s earlier so the device doesn't reach
  its no-app timeout; their pictures are unchanged.
