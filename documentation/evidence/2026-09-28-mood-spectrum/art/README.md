# Lane art: the bank becomes the device's designs and sounds

2026-09-28, branch `ms/art`, phases P1–P3 of [the plan](../PLAN.md) and its
decision D1 (the partition). No board, Bluetooth or webcam was used.

## What changed

- **One source.** `facegen` runs the bank's generator
  (`internal/tools/facegen/bank.mjs`) into its ignored `build/`, and
  `sfxgen` imports the bank. The 161 checked-in SVGs and the 140 copied
  scores are gone. The older moods' 308 designs come out byte for byte as
  `qa/v3-fingerprints.json` has them (facegen checks it every run); before
  the switch, all 161 shipped SVGs were compared with the bank's output
  (`cmp`, 0 differ) and with those fingerprints (0 differ).
- **The generator** tags each flip-book step's face, mouth and blink
  (`mood-art.mjs`); the V3 fingerprints didn't change.
- **facegen** reads V2, V3 and V4, allows a face and a mouth per step
  when only one shows at a time, per-mood variation counts, and each
  variation's `outcome` and `ctx`. Tracks and values are shared across
  scenes, which cut the faces' tables by about a quarter (facegen's
  estimate, 1,587 KiB to 1,165 KiB); in the firmware they take 1.19 MB.
- **Renderer**: 13 moods, 22 states, `render::fitting`, the visible
  face and mouth of a flip-book.
- **Sounds**: the bank's voice-first mix, baked for loops 0–7, loop-counted
  sparse, the duck rule by design, and each design's voice window.
- **Partition**: `huge_app.csv`, one 3 MB slot, NVS at 0x9000 as before.

## Checks that ran

| Check | Result |
| --- | --- |
| `node internal/boop-design/boop-sound-bank-v4/qa/check.mjs` | pass: 308 older designs byte-exact, 462 new plans checked |
| `make -C internal faces` (facegen `--check`, Chrome parity in RGB565) | the older moods' 161 V2 and 147 V3 designs come out as captured; 7,970 frames of 704 scenes match Chrome pixel for pixel; 7 min 40 s; its outputs are the committed ones, unchanged |
| `make -C internal fw-test` | 144 of 144 (was 140): test_face, test_scene and test_effects extended |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 changed pictures: the older moods draw as before |
| `make -C internal fw` | 2,496,539 bytes, 79.4% of the 3 MB slot (was 1,531,175 of 1.875 MB) |
| `make build`, `make -C internal test` | built; 278 of 278 Swift tests |
| `make -C internal tools-test` | 59, 11 and 3 tests OK |
| `.build/debug/Boop --snapshots DIR` | every pane rendered |

One Chrome difference was found and fixed in facegen, not the check: a
shape edge exactly on a pixel centre. Chrome rounds a half-pixel edge up,
so the centre goes to the shape above it; facegen had given it to the
shape below. Only new-mood designs had such edges (the cog, the cup and
annoyed's eyes), so no older design's frames changed.

## Pictures

- `designs.png`: a dozen designs as facegen, and so the device, draws
  them at 45% of their loop.
- `tiles.png`: the popover's tiles for all 13 moods, open and shut. A
  new mood's tile shuts its eyes with its flip-book's own blink step.

## For the owner and the next lanes

- The new art and sounds are integrated as-is (D9): they still need the
  owner's look and listen before main.
- Asleep and no app have two shared sets: the older moods' and the new
  moods'.
- The new moods' flip-books blink on their own clock, so the device's
  blink (and the blink that hides a design switch) doesn't show on them.
- The talking "o" sits where the first pack's mouths are (y 128–140
  plus the face's offset), a few pixels under the new moods' lips.
- The mix never picks the sad flood's short circuit, so that clip went.
