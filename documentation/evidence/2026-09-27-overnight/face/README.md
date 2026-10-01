# Overnight pass: the face (2026-09-27)

Device visuals only (`firmware/src/render/`), one commit per visual change
on branch `ovn/face`. All pictures come from the simulator (`boop-sim`)
with a frozen clock; nothing ran on the board or the webcam.

- `before-after.png`: eight scenario goldens at `17527f2` (left of each
  pair) and after this pass (right). Idle loses the empty strip's divider;
  working keeps equal eyes and loses the "brow" sliver at the strain's
  peak; asleep has two-block eye bars and a "zz ZZ" that stays on screen;
  needs you keeps idle's eye size under the bubble (85% instead of 75%);
  the cheer's heart is coral like the cheeks; listening shows its "o"; the
  heart and the sweat drop no longer overlap in a blend, and the drop is
  a tapered 3 px-block teardrop.
- `sweat-drop.png`: the working drop at 6×: the 2 px drop at `17527f2`,
  the flat-shouldered 3 × 4-block drop a review said read as a bottle, and
  the tapered 5 × 5-block drop that replaced it.
- `cheer-frames.png`: the cheer at 180-1650 ms. It lands squashed wide
  for 60 ms (350-390 ms), is round at the top of each hop, and after the
  hops the heart beats (small at 1450 ms) instead of holding still.

Motion was checked frame by frame at 10-25 ms steps across idle →
working, working → cheer, the tap's wiggle, listening, needs you arriving
and the working strain: the mouth and cheeks keep their offsets from the
eyes on every frame (they change only where the pose changes the eyes'
size), which `test_the_face_moves_as_one_sprite` also pins.

Checks that ran and passed: `make fw-test` (107 cases) and every scenario
in the simulator against the re-accepted goldens (0 expect failures, 0
changed pictures) at every commit of the branch, `make fw` (the board
build compiles; not flashed), and `make test` (210) and `make eval`
(24/24) for the one Mac-side change, the ".." on a cut project name.
