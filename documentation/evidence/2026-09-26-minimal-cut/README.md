# C1: cut to the minimal surface, 2026-09-26

The owner asked to cut Boop down to the states that matter most, so the
surface fits in their head, and to add features back one at a time. The
code before the cut is at git tag `v1-full`. What was kept is in
[BEHAVIORS.md](../../BEHAVIORS.md); what was parked is in
[FUTURE.md](../../FUTURE.md), "Parked from v1".

## Owner's choices

- Keep push-to-talk and the brain.
- Keep all mumbles.
- Tag, then delete the parked code, rather than switching it off.

## Decisions made while cutting

- A failed turn plays no moment. The session goes idle, and the brain's
  "turn failed" trigger still goes out, so it may mutter.
- Each finished turn sends its own `cheer`. A new moment replaces one that's
  playing, so a burst looks like one cheer.
- A `moment` may carry only `say`. That mumble plays over the current face.
  It keeps a cheer, nod, wiggle or shrug running, and it ends `listening` or
  `thinking`, because it's the reply they wait for.
- Any touch is a tap, sent on release.
- The device no longer shows Boop's name, since the stats screen was the
  only place it appeared.
- The popover's session list now comes from the app's own status, not from
  the `state` message.
- Old memory files (with a Growth section or a mood) and old `settings.json`
  keys (focus, away, the record) still load. The next write drops them.

## Checks (all run 2026-09-26, in the working tree)

| Check | Result |
| --- | --- |
| L0 Swift, `make test` | `✓ 170 passed, 0 skipped of 170 tests` |
| L0 firmware, `make fw-test` | `96 test cases: 96 succeeded` |
| L1, `tools/boopctl sim` | `10 scenarios, 0 expect failures, 0 new or changed pictures`, with 45 goldens (was 83 in 11 scenarios). Every new or changed picture was looked at before it was accepted |
| `make fw` | Builds. RAM 13.9% (45,532 B), flash 55.3% (1,087,099 B) |
| App snapshots, `Boop --snapshots` | Overview (asleep, working, needs you, offline) and settings looked at in light mode; nothing clipped |

## Follow-up: the pixel face

The owner then sent a reference render ([reference.jpg](reference.jpg)) and
asked for every animation to match it. The face is now pixel art
([UX.md](../../UX.md) §2):

- 3 px blocks with no anti-aliasing;
- window eyes of four panes;
- pink cheeks and a flat bar mouth;
- a pixel heart, sweat drop and "zzZZ".

The popover's face and the menu-bar icon follow. Poses and animations are
unchanged, so every animation takes the new look.

| Check | Result |
| --- | --- |
| `make fw-test` | `95 test cases: 95 succeeded`. The face tests were rewritten for the new look: crisp panes, lids cutting each half flat, softened corners and cheeks. The old smooth-lid tests are gone |
| `tools/boopctl sim` | All 45 pictures re-rendered and looked at, then accepted; then `0 new or changed pictures` |
| `make fw` | Builds. Flash 55.2% |
| `make test` | `✓ 170 passed` |
| `Boop --snapshots` | The popover face, setup face and menu-bar icons were looked at |

## Merged with the two-stage brain (A7)

`main` gained A7's two-stage brain while C1 was in progress.

- **Firmware:** the merge keeps C1's firmware as it is. It already
  included A7's removals (focus mode, touch-and-hold, the morning stretch).
- **Brain:** A7's design is kept: a classifier and a writer, with the
  `react`, `quiet` and `remember` outputs.
- **What C1 changes on top of A7:**
  - no hunger in the brain's inputs;
  - `cheer` with no size;
  - a failed turn gets no rule moment;
  - `react` keeps its ten feelings for the voice but shows no face. A
    mumble plays over the current face, and `silent` shows nothing.

After the merge: `make test` `✓ 173 passed`, `make fw-test` 95 passed,
`tools/boopctl sim` `0 new or changed pictures`, and `make fw` builds.

## Second cut: 7 things to show

The owner asked to go from 11 to 7: 4 states (asleep, idle, working, needs
you) and 3 animations (`cheer`, `wiggle`, `listening`).

- **Parked:** `nod`, `thinking`, `shrug` and the no-app look.
- **`listening`** now covers the wait for the reply, and ends on one of:
  - the reply's mumble;
  - an empty moment, which the Mac sends 8 s after Send, or at once when
    the mic can't start;
  - 8 s after BOOT is released.
- **No app:** the asleep face, with the unplugged icon.

| Check | Result |
| --- | --- |
| `make test` | `✓ 179 passed` |
| `make eval` | `5/5 scenarios passed` |
| `make fw-test` | `96 test cases: 96 succeeded` |
| `tools/boopctl sim` | 8 goldens removed, 7 changed and 4 added. Every new or changed picture was looked at. 41 goldens in 10 scenarios; `0 new or changed pictures` |
| `make fw` | Builds, flash 55.1% |

## Not yet run

- Flashing the board and L2 (`tools/boopctl run`): it needs the owner.
- L4 (`make e2e`) and a webcam look.
