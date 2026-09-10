# XP and progression

Current contract, 2026-09-11. There is no skill tree, spending or level-gated
behavior. [Growth UX](UX-GROWTH.md) defines progress and memory; the
[component catalog](BEHAVIORS.md#4-xp-levels-and-streaks) is the compact reference.

| Source | XP |
| --- | ---: |
| Started work period completes | 3 |
| First qualifying activity of a local day | 10 |

No session, token, check-in, goal-pass, retry or streak bonus. Boops can qualify
an active day but grant no separate XP. Approval decisions grant nothing.
There are no hourly or daily XP caps. Duplicate completion signals are ignored.

Cumulative XP at level L is `100 × (L−1) × L / 2 + 50 × (L−1)`. The next
level requires `100 × L + 50` more XP; no level cap. XP is a local progress
statistic and an input to the Markdown-guided model.

Streaks count consecutive active civil dates, without rest credits. Today is
not missed until tomorrow. A gap resets current streak, preserving best and XP.

Already earned XP and historical inventory remain. The store freezes existing
materialized awards; legacy ledger-only databases reconstruct their old XP
once using migration-only code. Future formula changes do not reprice history.
New task totals count completed turns. Named milestone keepsakes are deferred.

Implementation: [formula](../app/Boop/Core/Store/Growth.swift),
[store](../app/Boop/Core/Store/Store.swift),
[migration](../app/Boop/Core/Store/LegacyGrowthMigration.swift).
