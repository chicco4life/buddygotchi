# Phase 6 evidence: rituals, cosmetics, perch set, pick-up

Captured 2026-09-09 on the Waveshare AMOLED board with `tools/shots.py`
(cosmetics reset at the start of every sheet; each cell frozen with
`clock settle`). All 39 cells are goldens under
`firmware/esp32/tests/golden/ws-amoled164/`, 39/39 across two captures.
USB HIL: 62 passed. Not run: overnight battery (needs a battery unit),
BLE HIL, listening to motifs (no speaker on this board).

Owner review points: with a skin set, the body renders as a dark oval over
the tinted field (see cosmetic-crown); whether that reads as intended is an
art-direction call.
