# Hook fixtures

Raw hook payloads, one directory per agent:

- `claude-code/2026-09-08/` and `codex/2026-09-08/`: recorded from Claude
  Code 2.1.263 and Codex CLI 0.153.4 on that day.
- `<agent>/synthetic/`: hand-written sessions in the recorded payloads'
  shape, for cases the recordings don't cover: a Claude permission request
  with its matching `Notification`, and Codex requests its automatic
  reviewer handles (resolved inside the 2 s grace period) or that wait for
  a person.
- `e2e/`: the pipeline check's sessions with their checkpoints
  ([plan/VERIFICATION.md](../../../../plan/VERIFICATION.md) L4).

`boopdev replay` runs any of them through the adapter and the core; a line
`{"wait_ms": N}` moves its clock. `HookWireTests` walks every file and
checks that no `PRIVATE_…` marker reaches the hook line.

To record a new agent release, point its hooks at a script that appends
each payload (stdin) to a `.jsonl` file, run one short session, and put
the file in a new dated directory before claiming support for it.
