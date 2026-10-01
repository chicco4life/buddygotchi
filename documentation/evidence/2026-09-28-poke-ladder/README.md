# Poke ladder: glad, then miffed, then grumpy (2026-09-28)

One poke cheers (mood stays happy), two in a row turn Boop determined
("hmm"), three or more grumpy ("nope"). The run gate now starts at the
third poke (`TranscriptView.Config.answersRunFrom`), so the first two
reactions don't hold back the next poke.

Why: in the owner's log that day, Jev turned grumpy at 2–3 pokes, a
single poke got only a small face, and grumpy stayed on into later
single pokes, so Boop read as angry at once.

## Jev runs (jev-latest)

| Scenario | main's steering | This change |
| --- | --- | --- |
| `05-pokes-glad-miffed-grumpy` | — (new) | 10/10, then 5/5 in the full run |
| `16-poking-keeps-boop-angry` | 3/5 | 0/5 at first; 10/10 after grumpy's exit was reworded ("goes back to happy at whatever NOW is, but more pokes in a row"), then 5/5 |
| `23-poke-barrage-one-face` | — | 10/10, then 5/5 |
| `11-comeback-still-showing` | 5/10 | 2/10 with the finish/check-in sentence shortened to fit the budget; 19/20 with it restored, so it stays as it was and the 3-poke Example went instead (the grumpy mood and options carry "3+ pokes") |

Full `make eval` on the final steering: 33/34 passed in every run, the
one failure the known gap `20-no-flail`. `make -C internal test`: 274
passed.
