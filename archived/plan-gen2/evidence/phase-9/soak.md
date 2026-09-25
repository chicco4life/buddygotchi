# Soak and hardening, 2026-09-09, fw dev+f7b1937911ff, ws-amoled164

`tools/soak.py --minutes 15` on the v2 wire (states, cards answered both
ways once armed with the careful-stakes hold, held boops, screenshots),
app quit, board on USB.

| Metric | Value |
| --- | --- |
| Cycles | 256 |
| Card decisions | 64 |
| Boops | 21 |
| Screenshots verified (CRC) | 25 |
| Heap first / last | 198776 / 198776 |
| Heap minimum seen | 195108 (floor 60000) |
| Panics | 0 |
| Reboots | 0 |
| Uptime at end | 1163 s |

Heap floor re-baselined for the v2 firmware: 195 kB minimum over the run.

`tests/hil/test_hardening.py` (serial fuzz, watchdog, reboot soak): 5 passed,
board re-enumerated on USB after every reset this time. Full USB HIL: 82
passed with one order-sensitive flake (`test_unit_stable_across_reboot_and_debug_wake`
timed out once right after a reboot; passes alone). BLE HIL: 2 passed.
