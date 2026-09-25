# Phase 1 evidence: archived firmware renders the shim vocabulary

Captured 2026-09-08 on the Waveshare AMOLED board (firmware dev+239c2f4) over
USB with `buddyctl`. Each frame is shaped exactly as the Phase 1 heartbeat
mapper emits it for the corresponding creature state (`pet` is the legacy
projection). The frames were hand-built to the mapper's shape, not captured
from the app over BLE; the app cannot be launched by an agent (Bluetooth TCC).

| Creature state | Frame `pet` | Screenshot | Device persona |
| --- | --- | --- | --- |
| working (effort hard) | busy | shim-working.png | P_BUSY, sweat drop |
| needsYou (card, careful) | attention | shim-needsyou.png | P_ATTENTION, card armed |
| done (dance) | celebrate, celebrateLevel 3 | shim-done.png | P_CELEBRATE |
| uhoh (error) | error | shim-uhoh.png | P_DIZZY (this firmware's error face) |

Gotcha: the device was napping (accelerometer read face-down, screen off) and
silently ignored frames until `imu set 0 0 0.98` was sent over serial.
