# Hardware v2 (working notes)

Status: 2026-09-09, agent notes. The form factor, mount, battery, and board
are the owner's decisions and remain open. What the firmware phases assume:

- Bench board: Waveshare ESP32-S3 Touch AMOLED 1.64 (`ws-amoled164`), no
  speaker, IMU present, USB-C, native USB serial. Sound motifs exist in
  firmware but cannot be heard on this board.
- Posture detection uses the IMU only; a mount sensor is not assumed.
- Sleep is a dim frame, never off; the overnight battery test (Phase 6)
  needs a battery-backed unit on the bench.
- Per-unit key for growth signing is provisioned on first pair in software
  for prototypes (Phase 8); manufacture provisioning is open.
- Open: shell shape that both perches and pockets, mount type, battery
  capacity for a working day plus a dim night, second button confirmation,
  touch or not, speaker for production.
