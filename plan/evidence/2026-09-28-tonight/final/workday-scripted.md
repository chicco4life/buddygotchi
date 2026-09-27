<!-- python3 internal/tools/workday/workday.py run --brain scripted --state /tmp/fwd --out /tmp/fwd-out, then report /tmp/fwd-out/debug.jsonl, on main 8560cf59 -->
## /tmp/fwd-out/debug.jsonl

Reactions are to each kind of line that woke the brain, reacted/all: notable (failures, fixes, failed or stopped turns, turns of 10 min or more, pokes), clean finishes of 1–10 min, clean finishes under a minute, turn starts, heartbeats.

Mood changes on a routine line (a turn start, or a clean finish under 10 min) are split: back to happy (a mood fading), and any other (which the line shouldn't cause).

| Hour | Turns | Passes | Mood changes | … routine, to happy | … routine, other | Reactions | notable | 1–10 min | short | starts | quiet | Faces |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 44 | 0 | 0 | 0 | 44 | 0/0 | 7/7 | 15/15 | 22/22 | 0/0 | excited 44 |
| 10:00 | 29 | 63 | 0 | 0 | 0 | 63 | 7/7 | 1/1 | 26/26 | 29/29 | 0/0 | excited 63 |
| 11:00 | 36 | 74 | 0 | 0 | 0 | 74 | 4/4 | 3/3 | 31/31 | 36/36 | 0/0 | excited 74 |
| 12:00 | 6 | 12 | 0 | 0 | 0 | 12 | 0/0 | 2/2 | 4/4 | 6/6 | 0/0 | excited 12 |
| 13:00 | 7 | 18 | 0 | 0 | 0 | 18 | 4/4 | 4/4 | 2/2 | 7/7 | 1/1 | excited 18 |
| 14:00 | 34 | 76 | 0 | 0 | 0 | 76 | 9/9 | 2/2 | 30/30 | 35/35 | 0/0 | excited 76 |
| 15:00 | 14 | 27 | 0 | 0 | 0 | 27 | 0/0 | 3/3 | 11/11 | 13/13 | 0/0 | excited 27 |
| 16:00 | 38 | 74 | 0 | 0 | 0 | 74 | 1/1 | 3/3 | 33/33 | 37/37 | 0/0 | excited 74 |
| 17:00 | 7 | 14 | 0 | 0 | 0 | 14 | 1/1 | 1/1 | 5/5 | 7/7 | 0/0 | excited 14 |
| 18:00 | 0 | 1 | 0 | 0 | 0 | 1 | 0/0 | 0/0 | 0/0 | 0/0 | 1/1 | excited 1 |
| all | 193 | 403 | 0 | 0 | 0 | 403 | 26/26 | 26/26 | 157/157 | 192/192 | 2/2 | excited 403 |

Time in each mood: happy 578 min

Mood changes:

