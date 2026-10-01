# Overnight pass, core lane (2026-09-27)

Checks that ran on branch `ovn/core`, on the Mac only: no Bluetooth, no
board, no webcam. The orchestrator runs the hardware checks after the
merge.

## Unit tests and evals

- `make test`: 233 of 233 pass (210 before the lane).
- `make eval`: 24 of 24 pass (chatty and calm, no writer) after every
  commit that touched the core.

## A sibling subagent and a failing grep, end to end

`subagent-smoke.log` is `Boop --headless --link none --mode chatty
--writer none --trace` in a scratch state directory, fed by the built
`boop-hook` with `BOOP_SOCKET` set:

1. SessionStart, UserPromptSubmit.
2. Subagent `a1`: PreToolUse and PermissionRequest for `swift test`.
   The state gains `attn`.
3. Subagent `a2`: PreToolUse, then PostToolUseFailure, for
   `grep -rn "make test" docs`. `attn` stays: a sibling's tool calls
   don't answer `a1`'s request (ADAPTERS.md §4).
4. `a1`'s PostToolUse clears `attn`; Stop cheers. The failing grep has no
   topic (ADAPTERS.md §3), so it doesn't fail the turn.

## Hook cost

`hooktime.py <boop-hook>` runs the debug `boop-hook` 60 times on a
PreToolUse payload, with the socket missing so it gives up at once, and
drops the first 5 runs.

| Build | p50 | p90 |
| --- | --- | --- |
| With `.sortedKeys` in `HookLine.encoded` | 7.6 ms | 8.5 ms |
| Without it | 3.8 ms | 4.5 ms |

## Doctor

`skills/doctor/doctor.sh --headless`: 7 passed, 0 failed (hooks
registered, socket, synthetic round trip against a throwaway headless
app).
