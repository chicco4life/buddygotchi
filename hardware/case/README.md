# Boop Pebble Case (v1 form prototype)

Round tamagotchi-style enclosure for the Waveshare ESP32-S3-Touch-AMOLED-1.64
("Boop Pebble"). 64 mm wide, 23 mm deep. Flat face with a landscape screen
window, menu/reject button caps below the screen, big boop dome on top,
domed back, USB-C slot on the left.

Everything is generated from `boop-pebble-case.scad` (OpenSCAD). Compiled
STLs are in `stl/`, preview renders in `renders/`.

## What to print

| File | Qty | Notes |
| --- | --- | --- |
| `stl/front_shell.stl` | 1 | Face already oriented down on the bed. No supports needed (window bridges are short). |
| `stl/back_shell.stl` | 1 | Parting plane down. No supports. |
| `stl/boop_cap.stl` | 1 | Print **with supports** (flange overhangs). |
| `stl/face_cap.stl` | 2 | Head-face down. Tiny part — print both at once. |

Suggested settings: PLA or PETG, 0.2 mm layers, 3 walls, 15 % infill.
Total print time roughly 3–4 h on a typical bed-slinger.

## Measure before trusting (v1 caveats)

This is a **check-fit prototype**. Three dimensions were not measurable from
the docs and are parameters at the top of the `.scad` — verify with calipers
against the real board and regenerate if they differ:

- `display_stack` (default 2.5) — height of the glass above the PCB front
  face. Drives `standoff_h`; wrong value either crushes the glass or leaves
  the board rattling.
- `screen_dx` (default 0) — the active area is probably **not** centered on
  the board (there is likely an FPC chin), which also explains why the spec'd
  M2 holes land right at the window corners. Measure the offset of the lit
  area from board center along the long axis and set it; the window shifts,
  the standoffs stay at the spec'd 22.86 × 38.50 mm hole pattern.
- `usb_w` / `usb_h` / `usb_z` — the USB-C slot is deliberately oversized
  until the connector position is measured. The board mounts with USB-C
  facing **left**.

Known dimensions baked in from `research/eng/waveshare-amoled-port.md`:
PCB 28.6 × 43.5 mm, M2 holes at 22.86 × 38.50 mm, active area 22.3 × 36.1 mm.

## Hardware (not printed)

- 4× M2×5 self-tapping screws — board to standoffs (from the back of the PCB)
- 3× M2×8 self-tapping screws — back shell to front shell bosses
- 3× 6×6×4.3 mm through-hole tact switches, glued: two on the round pads
  inside the back shell (under the face caps), one on the block behind the
  boop bore (plunger facing the boop pusher)
- LiPo up to ~602030 (6 × 20 × 30 mm), 1.25 mm plug — lives in the cavity
  behind the board. **Meter connector polarity first** (per the port doc).

## Assembly

1. Drop the two face caps into their holes from inside the front shell,
   then the boop cap into its bore from inside (flange seats against the
   guide-tube shoulder).
2. Screw the board to the standoffs, screen against the window, USB-C left.
3. Glue tact switches on their pads; trim/shim cap stems so each cap sits
   proud at rest and clicks with ~1 mm of travel. Wire switches to header
   GPIOs per the port plan (boop can go to GPIO0/BOOT).
4. Connect battery, nest it behind the board, screw the back shell on.

No RST access in v1 — recovery flashing means opening the case (3 screws).

## Regenerating

```sh
cd hardware/case
# STLs
for p in front_shell back_shell boop_cap face_cap; do
  openscad -q -D "part=\"$p\"" --backend Manifold -o "stl/$p.stl" boop-pebble-case.scad
done
# renders
openscad -q -D 'part="assembly"' --imgsize=1200,1000 --camera=0,4,0,0,0,0,175 \
  -o renders/assembly-face.png boop-pebble-case.scad
```

`part` also accepts `assembly`, `exploded`, and `section` for visual checks
(the section view is the quickest way to sanity-check wall thickness and
button/switch geometry after changing parameters).
