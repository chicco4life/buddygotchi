# Brain conversation — 2026-09-26

L5 with Apple's model (`apple:27.0`), the 52 fixture triggers 3 minutes
apart, static tools with limit lines. Baseline is
[A3 run 5](../v1-build/A3/l5-apple-run5.txt) (one-shot calls, limited tools
not offered).

| Run | Quiet answers | Spoke on event / tap / talk | Past a limit | Latency p50 event / tap / talk |
| --- | --- | --- | --- | --- |
| Baseline (A3 run 5) | 7/50 | 5/24 · 4/8 · 3/14 | 0 | 1.7 · 1.7 · 2.1 s |
| `--history 0` (static tools only) | 8/51 | 1/23 · 2/8 · 5/16 | 23 (19 `note` on events) | 2.2 · 1.9 · 2.2 s |
| `--history 4` | 30/51 | 0/24 · 0/8 · 4/16 | 11 (10 `note` on events) | 2.1 · 1.8 · 1.9 s |
| Budget only (up to 33 exchanges) | 38/50 | 0/23 · 3/8 · 1/15 | 4 | 2.6 · 2.5 · 3.4 s |

Quiet answers by kind with `--history 4`: event 11/24, tap 8/8, talk 10/16
(without history: 2/24, 3/8, 3/16).

- The `say limit:` line works: `say` was called past its limit once or
  twice per run.
- Offering `note` on events brings back the misuse in
  ARCHITECTURE.md §11 (2026-09-26): the model calls it on most events. The
  harness drops those calls, but they take the place of speech.
- History makes the model copy its earlier quiet answers, most on taps and
  talk. With no cap, latency grows with history (p50 2.0 s at 0–4
  exchanges, 3.6 s at 25+).
