# Phase 2 evidence: v2 firmware renders the six-state contract

Captured 2026-09-08 on the Waveshare AMOLED board running the Phase 2 firmware
(`contract: 2`), driven over USB by `tools/shots.sh`: each cell is a RenderState
v2 frame sent live, settled, then frozen with `clock <device ms>` before the
screenshot. These 21 PNGs are also the goldens under
`firmware/esp32/tests/golden/ws-amoled164/` (`golden.py check` 21/21 at 0.000).

Cells: six states, three efforts, three cheer sizes, three uh-oh kinds, a card
at each stakes level, a Korean bubble, a pending gift orb, and a travel frame.

Verified alongside: `tests/hil/test_usb.py` 31 passed, `test_hardening.py`
5 passed (heap floors, reboot soak, serial fuzz). Not run: BLE HIL (needs the
Mac paired and the app launched by the user).
