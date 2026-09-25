# F4: Bluetooth on the device — evidence

Run 2026-09-26 on branch `v1-overnight`. Device checks ran against the
firmware committed as `6dd4ae2` (flashed from the working tree just before
that commit, so `ping` reported `41ef83f0a3-dirty`). Afterwards the board
was reflashed from `3707c8e` (same firmware sources) and left advertising
on the face, heap 84 KB. Outputs:
[perf-motion.json](perf-motion.json) and [soak.json](soak.json).

## What was built

- **Nordic UART peripheral** (`firmware/src/link/ble.*`), on NimBLE-Arduino
  2.x. It advertises as `Boop-XXXX` (the last 4 hex digits of the Bluetooth
  MAC; this board is `Boop-54FE`) with the NUS service UUID, and has no
  pairing or encryption, as PROTOCOL.md §2 says for v1. It asks for a
  247-byte MTU and restarts advertising after a disconnect.
- **Classic Bluetooth's memory is released** before NimBLE starts, and
  Bluetooth starts after the canvas is allocated, so the canvas still gets
  its contiguous 76.8 KB block.
- **Packets to lines and back** (`firmware/src/app/packets.h`, pure C++).
  NimBLE's task puts received bytes into a lock-free single-writer ring; the
  main loop drains it into the same `LineReader` USB uses and calls
  `Device::handleLine(..., Link::kBle)`, so dispatch is shared and the core
  stays single-threaded. Replies go through a `PacketWriter` that holds a
  line until its newline, then sends it in notifications no bigger than the
  negotiated MTU minus 3. Lines over 512 bytes are dropped whole.
- **`status`** (PROTOCOL.md §4): sent on a Bluetooth connect, every 60 s on
  the link the Mac last spoke on, and over USB when the Mac first speaks (or
  speaks after 30 s of silence), since USB has no connection event. The ID
  is `b00p-` plus the same 4 hex digits; `usb` is always 1 on this board.
- **`input`** goes to the link the Mac last spoke on, as before, so a tap
  reaches the Mac over Bluetooth once it's connected.
- **`dbg.ping`** now reports `ble` (`off`, `adv` or `conn`) and the
  advertised `name`.

## Checks

| Check | Result |
| --- | --- |
| L0 `make fw-test` | Passed: 61/61. New: BLE packets of 1–244 bytes reassemble through the ring into the same lines; the ring drops what doesn't fit and wraps; the writer sends whole lines in MTU-sized chunks and drops overlong ones; `status` on connect and every 60 s with input going out over BLE; USB `status` when the Mac first speaks |
| L2 `ping` advertising | Passed: `"ble":"adv","name":"Boop-54FE"`, heap 84.0 KB, heap_min 83.9 KB (target ≥ 60 KB) |
| L1 `boopctl sim` | Passed: 10 scenarios, 0 expect failures, 0 new or changed pictures |
| L2 `boopctl run` | Passed with Bluetooth on: 10 scenarios, 0 expect failures, all 80 screenshots identical to the simulator's |
| Perf with Bluetooth on | Passed, unchanged: `perf --seconds 30 --motion` gave min **45 fps** (mean 59.3; F3 was 45 / 58), heap_min 82.7 KB, no reset |
| Soak with Bluetooth on | Passed: `soak --minutes 20` with Bluetooth advertising: no reset, heap_min 82.6 KB at start and end (0 drift), still answering, ended on the face |
| Real connection | Not checked here, by design: agents can't use the Mac's Bluetooth or `bleak`. It's on the morning checklist (VERIFICATION.md L6) |

## Decisions

- Over USB, `status` goes out when the Mac first speaks, or speaks after
  30 s of silence (PROTOCOL.md §4, ARCHITECTURE §11).
- `dbg.ping` reports `ble` and `name` (VERIFICATION.md §3, ARCHITECTURE §11).
- Bluetooth costs about 75 KB, not the 45–60 KB first budgeted; the 60 KB
  free-heap target still holds with about 20 KB to spare (DEVICE.md §6).
- The namespace is `links`, not `link`, which would clash with POSIX
  `link()`.
