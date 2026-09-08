# Boop Pebble Case v3 — bao zi (form prototype)

Desk-buddy enclosure for the Waveshare ESP32-S3-Touch-AMOLED-1.64
("Boop Pebble"). The body is a plump steamed-bun ellipsoid on a flat
bottom, with the face — screen window, menu/reject caps below it, and
the board behind — inset as a small pillowed facet that tilts back 25°
from vertical so the screen looks up at you. A brow rolls over the top
of the window, and the boop dome nestles in a dimple on the crown.
Roughly 72 mm wide × 62 mm tall × 76 mm deep.

Geometry gotcha for future edits: the brow sphere sits proud of the
face plane, so the body hull "tents" the whole facet forward ~1.5 mm —
face cuts (window, button holes) must punch well past local z=0, and
anything added near the face plane should be checked with
`part="section"` and the `shell_dbg` part.

Everything is generated from `boop-pebble-case.scad` (OpenSCAD). Compiled
STLs are in `stl/` (gitignored, regenerate below), renders in `renders/`.

## What to print

| File | Qty | Notes |
| --- | --- | --- |
| `stl/front_shell.stl` | 1 | Faceplate, face down on the bed. No supports (window bridges are short). |
| `stl/back_shell.stl` | 1 | Body bowl, parting plane down. No supports; the flat tummy prints as a steep facet. |
| `stl/boop_cap.stl` | 1 | Print **with supports** (flange overhangs). |
| `stl/face_cap.stl` | 2 | Head-face down. Tiny part — print both at once. |

Suggested settings: PLA or PETG, 0.2 mm layers, 3 walls, 15 % infill.

## Measure before trusting (calipers, then regenerate)

Parameters at the top of the `.scad`, unverifiable from docs:

- `display_stack` (2.5) — glass height above the PCB front face; drives
  standoff height. Wrong → crushed glass or rattling board.
- `screen_dx` (0) — the active area is probably offset from board center
  (FPC chin). Measure and set; the window shifts, the standoffs stay on
  the spec'd 22.86 × 38.50 mm hole pattern.
- `usb_w` / `usb_h` / `usb_z` — USB-C slot is oversized until measured.
  The board mounts with USB-C toward the buddy's right (your **left** as
  you face it).
- `tilt` (25°) — how far the face leans back. Taste parameter.

Known dims baked in from `research/archived/eng/waveshare-amoled-port.md`:
PCB 28.6 × 43.5 mm, M2 holes at 22.86 × 38.50 mm, active area 22.3 × 36.1 mm.

## Hardware (not printed)

- 4× M2×5 self-tapping screws — board to standoffs (from the back of the PCB)
- 3× M2×10 self-tapping screws — shell screws; they sit in deep wells and
  drive through the three small channel openings on the buddy's back
- 3× 6×6×4.3 mm tact switches, glued: two on the columns inside the body
  bowl (under the face caps), one on the block behind the boop bore
- LiPo up to ~602030, 1.25 mm plug — sits on the bowl floor.
  **Meter connector polarity first** (per the port doc).

## Assembly

1. Drop the two face caps into their holes from inside the faceplate, then
   the boop cap into its bore from inside (flange seats on the guide-tube
   shoulder). The shell seam intentionally passes behind the boop crest.
2. Screw the board to the standoffs, screen against the window, USB-C
   toward the buddy's right.
3. Glue tact switches on their columns/block; trim or shim cap stems so
   each cap sits proud at rest and clicks with ~1 mm travel. Wire to
   header GPIOs per the port plan (boop can go to GPIO0/BOOT).
4. Battery on the bowl floor, then mate the faceplate and drive the three
   M2×10 screws through the back wells.

No RST access in v1 — recovery flashing means opening the case.

## Regenerating

```sh
cd hardware/case
for p in front_shell back_shell boop_cap face_cap; do
  openscad -q -D "part=\"$p\"" --backend Manifold -o "stl/$p.stl" boop-pebble-case.scad
done
openscad -q -D 'part="assembly"' --imgsize=1200,1000 --camera=0,0,26,72,0,180,215 \
  -o renders/assembly-face.png boop-pebble-case.scad
```

`part` also accepts `assembly`, `exploded`, `section`, and `shell_dbg`
(hollow body only, face-on — for debugging the hull). The section view
is the quickest sanity check on walls and button/switch geometry after
changing parameters; the face plane is world-tilted, so eyeball new
features there before printing.
