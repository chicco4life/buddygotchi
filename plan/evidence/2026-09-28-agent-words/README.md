# "claude" and "codex" join the topic words

2026-09-28, `boopdev eval` against `jev:jev-latest`, first on top of
`d76ed324` (a cheer names whose turn it cheers), then rebased onto
`a241bb18` (pokes make Boop glad, then miffed, then grumpy).

The agents' names are the filler topic word: Jev picks one when a turn
ends and no other topic fits. Both were newly recorded (`voicegen`:
`claude` 0.32 s, `codex` 0.48 s; the pack is 235 KB), so the board needs a
reflash.

| Run | Result |
| --- | --- |
| Option "NOW is claude's work and no other topic word fits", not for work still going | `33` 10/10 with "claude"; full eval 32/34, `15` 0/3: every quiet check-in said "claude" |
| Option tied to a turn ending (done, stopped or failed), not for the agent still working (committed) | `15`, `33`, `03`, `11` 5/5 each |
| Full eval, that wording, on `d76ed324` | 33/34; `20` a known gap |
| Full eval, same wording, rebased onto `a241bb18` | 32/35; `20` a known gap; `30` 1/3 ("claude" and "bug" near even, 0.52 / 0.43); `27` 2/3, one pass past the 1500 ms deadline |
| Option says the name loses to any other topic, the check-in first in its not-for (committed) | `30`, `33`, `15` 5/5 each |

Saying what the option is for worked where saying what it's not for
didn't: with "work still going" only in its not-for, Jev still filled
each check-in with the name. After the rebase (main's talk Examples) the
name crept up on a real topic, so its not-for says the topic's word wins;
putting that before "still working" let one check-in say the name again
(`15` 4/5), so the check-in comes first.

No eval plays codex: the runner's events are all claude's.
