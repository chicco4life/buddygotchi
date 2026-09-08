# UX: Growth

Status: first draft, 2026-09-09, written by the agent to unblock Phase 4 while
the owner was away. Every number here is an assumption to tune; the
mechanism is what Phase 4 builds. Refines `VISION.md` §10.

## XP formula (public, one screen)

| Source | XP | Notes |
| --- | --- | --- |
| Turn completed | 3 | The unit of work the buddy cheers for |
| Task finished | 8 | A turn that ends a goal with a pass, or a session that ends with completed work |
| Hard-won pass moment | +12 | On top of the task |
| Active day | 10 | First activity of a local day |
| Streak bonus | +1 per streak day, capped at +10 | Added to the active-day award |
| Session started | 2 | Presence |
| Check-in (boop, pet, collect) | 1, capped 20/day | Bond, lightly |
| Tokens used | 1 per 100k output tokens, capped 10/day | Best effort, Claude Code and Codex only |

Never a source: approvals or denials.

No daily cap on the total; the leaderboard ranks lifetime XP. Anti-farming is
plausibility limits (no more than 60 turns/hour counted) and device signing
(Phase 8).

## Level curve

Cumulative XP to reach level L: `100 × (L−1) × L / 2 + 50 × (L−1)` for
L ≥ 2 (level 2 at 150, level 5 at 1,200, level 10 at 4,950, level 20 at
19,950, level 30 at 44,950). Shown as level plus an XP bar to the next level.

## Streaks

Consecutive active local days. One rest day banked automatically per seven
active days, up to three banked; a missed day consumes a banked rest day
before breaking the streak. Losing a streak resets the counter only.

## Cosmetic unlocks (schedule)

| Level | Unlock |
| --- | --- |
| 2 | Second skin color ("sky") |
| 3 | Happy wiggle micro-idle |
| 5 | Skin "mint"; the sulk expression |
| 8 | Accessory "sprout" |
| 10 | Silhouette "round" (first silhouette change); new hop chirp |
| 15 | Skin "ember"; the big dance variant |
| 20 | Accessory "scarf"; silhouette "tall" |
| 30 | Skin "midnight"; accessory "crown" |

Milestone keepsakes (not level-gated): first dance, 100th task, 30-day
streak, first late-night session.

## Hidden bond

0–255, monotonic. +1 per active day, +1 per collected gift (max +3/day), +2
per greet after ≥ 1 day away. Drives greet warmth and how much the buddy
remembers; never shown as a number.

## Traits

Four axes 0–255, start 128 (cheek set by the setup temperament: earnest 64,
cheeky 192). Daily deltas capped at ±3 per axis:
energy ↑ with morning starts and many turns, ↓ with late nights;
cheek ↑ with denials and rate limits survived, ↓ with long quiet sessions;
warmth ↑ with check-ins and greets; curiosity ↑ with new projects and many
distinct tools.
