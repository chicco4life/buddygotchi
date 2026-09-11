# UX: Growth

Current contract, 2026-09-11.

## Progress

Completed turns earn 3 XP; an active local day earns 10 XP once. No other new
award sources or XP rate limits. Duplicate completion signals cannot earn twice.
Session/work activity and boops qualify a day; approvals do not award XP.
Existing XP stays earned, including historical sources. Accounting never
reprices materialized history. Task counts represent completed turns.

XP is one cumulative counter with no product cap, levels, targets or level-up effects.
The Mac shows total XP, completed agent turns (labeled Turns), and current streak.
A compact GitHub-style grid shows twelve Sunday-first weeks through today; future
cells are blank. Daily turn counts come from persisted source units, never XP
estimates. Fill intensity bands are 1–4, 5–14, 15–29 and 30+ completed turns.
Hover shows the date and exact count. Active days with zero completions get an
outline; missing days are empty. History failures are explicitly labeled.
Appearance stays fixed; historical inventory and earned XP remain stored.
Legacy level/xpNext fields remain compatibility-only at 1/0, with no live formula.

Streaks count consecutive active local dates, with today allowed to remain
incomplete until tomorrow. Missed days reset current streak; best streak and
XP survive. No rest-day credits or streak bonuses.

Local share-card export is removed for now. Leaderboards, sync, rank UI and device signing
are deferred to [IDEAS.md](IDEAS.md).

## Personality and remembered profile

Personality lives directly in BEHAVIOR.md. Private learning keeps a small profile; the current shared display context uses
recent remarks but does not yet include profile lines or episode memories. Numeric energy, cheek, warmth, curiosity and
bond are inactive; existing values are retained without updates or model use.
There are no usual-hour, known-project or lifetime-session familiarity inputs.

Once daily after twenty inactive minutes on AC power, the local model may select
up to five supported memories. Facts last 30 days. Profile lines persist and are
inspectable/deletable. The guide steers learning; invalid/unavailable output
leaves memory unchanged. See [Voice](UX-VOICE.md).



XP accounting, base state and approval authority remain outside model control.
Approval decisions are excluded from learning evidence.
