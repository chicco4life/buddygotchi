# Working day reruns, 2026-09-28 (python3 internal/tools/workday/workday.py report …)

Rerun 1 is the tool as the tune lane committed it (e337c3d1); rerun 2 has the settle barrier. Same seed (1), same steering, jev:jev-latest, warm (a make eval ran just before).

## rerun-1/debug.jsonl

Reactions are to each kind of line that woke the brain, reacted/all: notable (failures, fixes, failed or stopped turns, turns of 10 min or more, pokes), clean finishes of 1–10 min, clean finishes under a minute, turn starts, heartbeats.

Mood changes on a routine line (a turn start, or a clean finish under 10 min) are split: back to happy (a mood fading), and any other (which the line shouldn't cause).

| Hour | Turns | Passes | Mood changes | … routine, to happy | … routine, other | Reactions | notable | 1–10 min | short | starts | quiet | Faces |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 44 | 0 | 0 | 0 | 17 | 0/0 | 7/7 | 10/15 | 0/22 | 0/0 | happy 14, excited 3 |
| 10:00 | 29 | 63 | 5 | 1 | 0 | 26 | 7/7 | 1/1 | 18/26 | 0/29 | 0/0 | happy 14, grumpy 4, excited 4, proud 3, determined 1 |
| 11:00 | 36 | 74 | 2 | 1 | 1 | 27 | 4/4 | 3/3 | 20/31 | 0/36 | 0/0 | happy 20, excited 3, grumpy 2, proud 2 |
| 12:00 | 6 | 12 | 0 | 0 | 0 | 6 | 0/0 | 2/2 | 4/4 | 0/6 | 0/0 | happy 5, excited 1 |
| 13:00 | 6 | 17 | 2 | 0 | 0 | 8 | 4/4 | 3/3 | 1/2 | 0/7 | 0/1 | excited 2, happy 2, proud 2, determined 1, grumpy 1 |
| 14:00 | 34 | 75 | 4 | 1 | 0 | 29 | 9/9 | 3/3 | 17/29 | 0/34 | 0/0 | happy 17, grumpy 5, excited 3, proud 2, determined 1, sad 1 |
| 15:00 | 15 | 29 | 1 | 1 | 0 | 9 | 0/0 | 4/4 | 5/11 | 0/14 | 0/0 | happy 5, proud 3, excited 1 |
| 16:00 | 38 | 74 (4 dropped) | 0 | 0 | 0 | 24 | 1/1 | 3/3 | 20/33 | 0/37 | 0/0 | happy 20, excited 3, determined 1 |
| 17:00 | 7 | 14 (4 dropped) | 0 | 0 | 0 | 4 | 0/1 | 1/1 | 3/5 | 0/7 | 0/0 | happy 4 |
| 18:00 | 0 | 1 | 0 | 0 | 0 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/1 | – |
| all | 193 | 403 (8 dropped) | 14 | 4 | 1 | 150 | 25/26 | 27/27 | 98/156 | 0/192 | 0/2 | happy 101, excited 20, grumpy 12, proud 12, determined 4, sad 1 |

Time in each mood: happy 446 min, proud 72 min, grumpy 51 min, sad 7 min, determined 4 min

Mood changes:
- 10:08 happy → determined (notable): claude's tests failed again on "api", 2 in a row.
- 10:10 determined → grumpy (notable): claude's tests failed again on "api", 3 in a row.
- 10:12 grumpy → proud (notable): claude's tests passed on "api" after 3 failures in a row.
- 10:25 proud → happy (start): claude started turn 3 on "fix-nav" (landing), right after its last one.
- 10:47 happy → grumpy (notable): You poked Boop 4 times in 1 s.
- 11:08 grumpy → proud (short): claude finished turn 23 on "fix-nav" (landing): done after 14 s, a short turn, 3 tools.
- 11:31 proud → happy (start): codex started turn 9 on "boop", after a long break.
- 13:54 happy → determined (notable): claude's build failed again on "fix-nav" (landing), 2 in a row.
- 13:56 determined → proud (notable): claude's build passed on "fix-nav" (landing) after 2 failures in a row.
- 14:06 proud → happy (start): claude started turn 44 on "fix-nav" (landing), right after its last one.
- 14:22 happy → grumpy (notable): You poked Boop 4 times in 1 s, again after a long break.
- 14:50 grumpy → sad (notable): claude finished turn 49 on "api": failed after 14 min, a very long turn, 33 tools (3 failed). Tests failing.
- 14:57 sad → proud (notable): claude's tests passed on "api" after 4 failures in a row.
- 15:23 proud → happy (start): claude started turn 54 on "api", a while after its last one.

## rerun-2/debug.jsonl

Reactions are to each kind of line that woke the brain, reacted/all: notable (failures, fixes, failed or stopped turns, turns of 10 min or more, pokes), clean finishes of 1–10 min, clean finishes under a minute, turn starts, heartbeats.

Mood changes on a routine line (a turn start, or a clean finish under 10 min) are split: back to happy (a mood fading), and any other (which the line shouldn't cause).

| Hour | Turns | Passes | Mood changes | … routine, to happy | … routine, other | Reactions | notable | 1–10 min | short | starts | quiet | Faces |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 44 (2 dropped) | 0 | 0 | 0 | 17 | 0/0 | 7/7 | 10/15 | 0/22 | 0/0 | happy 13, excited 4 |
| 10:00 | 29 | 63 | 5 | 1 | 0 | 26 | 7/7 | 1/1 | 18/26 | 0/29 | 0/0 | happy 13, excited 5, grumpy 4, proud 3, determined 1 |
| 11:00 | 36 | 74 | 2 | 1 | 1 | 30 | 4/4 | 3/3 | 23/31 | 0/36 | 0/0 | happy 23, excited 3, grumpy 2, proud 2 |
| 12:00 | 6 | 12 | 0 | 0 | 0 | 6 | 0/0 | 2/2 | 4/4 | 0/6 | 0/0 | happy 5, excited 1 |
| 13:00 | 6 | 17 | 2 | 0 | 0 | 8 | 4/4 | 3/3 | 1/2 | 0/7 | 0/1 | excited 2, happy 2, proud 2, determined 1, grumpy 1 |
| 14:00 | 34 | 75 | 4 | 1 | 0 | 29 | 9/9 | 3/3 | 17/29 | 0/34 | 0/0 | happy 17, grumpy 5, proud 3, excited 2, determined 1, sad 1 |
| 15:00 | 15 | 29 | 1 | 1 | 0 | 9 | 0/0 | 3/3 | 6/12 | 0/14 | 0/0 | happy 6, excited 2, proud 1 |
| 16:00 | 38 | 74 | 0 | 0 | 0 | 26 | 1/1 | 3/3 | 22/33 | 0/37 | 0/0 | happy 22, excited 3, determined 1 |
| 17:00 | 7 | 14 | 1 | 0 | 0 | 5 | 1/1 | 1/1 | 3/5 | 0/7 | 0/0 | happy 3, excited 2 |
| 18:00 | 0 | 1 | 1 | 0 | 0 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/1 | – |
| all | 193 | 403 (2 dropped) | 16 | 4 | 1 | 156 | 26/26 | 26/26 | 104/157 | 0/192 | 0/2 | happy 104, excited 24, grumpy 12, proud 11, determined 4, sad 1 |

Time in each mood: happy 369 min, excited 81 min, proud 68 min, grumpy 51 min, sad 7 min, determined 4 min

Mood changes:
- 10:08 happy → determined (notable): claude's tests failed again on "api", 2 in a row.
- 10:11 determined → grumpy (notable): claude's tests failed again on "api", 3 in a row.
- 10:12 grumpy → proud (notable): claude's tests passed on "api" after 3 failures in a row.
- 10:25 proud → happy (start): claude started turn 19 on "api", a while after its last one.
- 10:48 happy → grumpy (notable): You poked Boop 4 times in 1 s.
- 11:08 grumpy → proud (start): claude started turn 23 on "fix-nav" (landing), right after its last one.
- 11:31 proud → happy (start): claude started turn 28 on "api", a while after its last one.
- 13:54 happy → determined (notable): claude's build failed again on "fix-nav" (landing), 2 in a row.
- 13:56 determined → proud (notable): claude's build passed on "fix-nav" (landing) after 2 failures in a row.
- 14:06 proud → happy (start): claude started turn 44 on "fix-nav" (landing), right after its last one.
- 14:22 happy → grumpy (notable): You poked Boop 4 times in 1 s, again after a long break.
- 14:50 grumpy → sad (notable): claude finished turn 49 on "api": failed after 14 min, a very long turn, 33 tools (3 failed). Tests failing.
- 14:57 sad → proud (notable): claude's tests passed on "api" after 4 failures in a row.
- 15:19 proud → happy (start): claude started turn 53 on "api", a while after its last one.
- 17:21 happy → excited (notable): claude finished turn 1 on "docs" (landing): done after 16 min, a very long turn, 20 tools. Docs edited.
- 18:42 excited → happy (quiet): Nothing has happened for 1 hour.

