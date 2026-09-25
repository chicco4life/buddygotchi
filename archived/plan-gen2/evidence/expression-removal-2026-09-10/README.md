# Agent expression removal — 2026-09-10

- `make test`: 390 passed, zero skipped; includes legacy drawing round-trip,
  MCP cleanup isolation and offscreen snapshots.
- `make build`: Boop and BoopSignal passed.
- `tools/pio_ws.sh run -e ws-amoled164`: shipping firmware build passed.
- Activity snapshot reviewed: agent messages and keepsake shelf are absent;
  XP history, share card and leaderboard remain.
- No app launch, firmware flash or hardware verification performed.

The maintenance calendar/power test now injects a voice stub so live-model
punctuation cannot make its unrelated assertions nondeterministic.
