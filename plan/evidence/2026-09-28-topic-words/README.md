# "bug", "merge" and "review" join the topic words

2026-09-28, `boopdev eval` against `jev:jev-latest`, on top of
`314a2ead` (the moods the words bring).

The three were recorded already. Jev reads them from your prompt and the
agent's last message, the notes under a turn's start and end, so no hook
tags them.

| Run | Result |
| --- | --- |
| Three topic Examples in PERSONALITY | `30`–`34` 5/5 each, but `boop` 729 tokens, over its 600 budget |
| One line naming the words, no Examples (committed) | `boop` 592 tokens; `30`–`34` 10/10 each |
| Full eval | 31/34; `20` a known gap; `16` 4/5 and `18` 0/3 |
| `18`, main / branch | 5/15 / 4/15: the same mood bounce (determined → happy → determined) on both, so not this change |
| `16`, main / branch | 13/15 / 12/15: a barrage leaving Boop grumpy, as main's own evidence notes (1 in 10) |

The option meanings alone were enough: the topic question is judged by
PERSONALITY's Examples, and with none for these words Jev still named
each from the last message, and picked none for a question answered and
a rename (`33`).
