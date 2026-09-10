# UX: Growth

Current contract, 2026-09-11.

## Progress

Completed turns earn 3 XP; an active local day earns 10 XP once. No other new
award sources or XP rate limits. Duplicate completion signals cannot earn twice.
Session/work activity and boops qualify a day; approvals do not award XP.
Existing XP stays earned, including historical sources. Accounting never
reprices materialized history. Task counts represent completed turns.

Level L begins at `100 × (L−1) × L / 2 + 50 × (L−1)` cumulative XP. XP buys
nothing and gates nothing. Appearance stays default skin, no accessory, default
silhouette. Historical inventory is retained without new milestone creation.

Streaks count consecutive active local dates, with today allowed to remain
incomplete until tomorrow. Missed days reset current streak; best streak and
XP survive. No rest-day credits or streak bonuses.

Local share-card export remains. Leaderboards, sync, rank UI and device signing
are deferred to [IDEAS.md](IDEAS.md).

## Personality and remembered profile

Energy, cheek, warmth, curiosity and bond are 0–255 model context. Existing
values are retained. BEHAVIOR.md steers what they mean, when to change them,
and which evidence-backed memories to save. No hard-coded morning/late-night,
test-first, project-recurrence or check-in-to-trait rules remain. Active days
and return greetings no longer automatically add bond.

Once per day after 20 minutes inactive and on AC power, the local model may
propose up to five memories and ±3 changes per axis. Code validates evidence
references, supported axes, numeric bounds and text lengths; it does not prove
semantic truth. Invalid/unavailable output leaves profile and traits unchanged.
Stored facts last 30 days; selected profile lines persist and remain deletable.
The guide's default is gradual learning, no penalties for absence or failure,
and no unsupported guesses. Edit that file to steer personality and memory.

XP accounting, base state and approval authority remain outside model control.
Approval decisions are excluded from learning evidence.
