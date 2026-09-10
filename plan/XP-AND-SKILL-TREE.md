# XP and skill tree

## Settings policy revision — 2026-09-10

Current owner direction supersedes cosmetic selection described below: the app uses a fixed default appearance with no accessory and no user customization. XP, growth and inventory history are retained.

Status: implementation reference, 2026-09-10. Documents the current XP formula,
level progression and independent appearance catalog. Numbers are implemented defaults, still
subject to balance tuning. Companion to [UX-GROWTH.md](UX-GROWTH.md).

## What progression means

Buddy grows through coding activity and occasional interaction. The Mac app
records awards, calculates XP and levels, and sends progress to the device.
The ESP32 renders that progress; it does not independently decide how much XP
a coding task deserves. Local progression does not require leaderboard opt-in.

**XP is for bragging rights, not access.** There is no skill tree, unlock ladder,
skill-point balance or XP spending. Every implemented behavior and supported
appearance is available from the start. Levels, streaks, keepsakes and optional
rankings describe progress; they do not make Buddy more capable.

This replaces the original level-gated schedule at the owner's request
(2026-09-10): behavior and progression should be independent.

## Earning XP

| Source | Award | Counting rule |
| --- | ---: | --- |
| Session started | 2 XP | Recorded session-start award |
| Turn completed | 3 XP | Up to 60 counted turns per rolling hour **per session** |
| Task finished | 8 XP | Recognized goal completion, or session ending with completed work |
| Hard-won pass | +12 XP | Additional award for the recognized moment |
| Active day | 10 XP | First qualifying activity of a local calendar day |
| Streak bonus | +1–10 XP | Current active-day streak, capped at 10; added to the daily award |
| Check-in | 1 XP | Boop, pet or collect events; at most 20 awarded check-ins per local day |
| Output tokens | 1 XP / 100,000 | Reported output tokens accumulate across the day; at most 10 XP/day |

Awards stack when their events are recognized. A completed turn that also
finishes a task and earns a hard-won-pass moment can award `3 + 8 + 12 = 23 XP`.
Starting a session on the first active day adds `2 + 10 + 1 = 13 XP` separately.
This is an illustrative combination, not a promise that every successful command
is classified as a completed task or hard-won pass.

**Approving and denying requests never award XP.** There is no overall daily XP
cap. The turn limit does not cap session or task awards; current limits are not
comprehensive anti-farming protection. Token accounting is best effort and
supports reported Claude Code/Codex usage; missing usage cannot earn token XP.

## Levels

Buddy starts at level 1 with zero XP. For level L, the cumulative threshold is:

```text
XP required = 100 × (L − 1) × L / 2 + 50 × (L − 1)
```

Going from level L to L+1 requires an additional `100 × L + 50` XP. XP is
cumulative and is not spent when leveling or equipping a cosmetic. The growth
snapshot exposes total XP, current level, XP remaining to the next level, and
today's XP. There is no implemented level cap or reward threshold.

## Appearance and behavior availability

All supported options are available at zero XP, including on existing stores:

| Category | Options |
| --- | --- |
| Skin | Default, sky, mint, ember, midnight |
| Accessory | None, sprout, scarf, crown |
| Silhouette | Default, round, tall |
| Behavior | All implemented states, greetings, boops, petting, motion reactions and completion celebrations |

Equipping validates that an appearance exists in the catalog, not that the pet
has earned it. Choosing an appearance neither spends XP nor changes the level.
Old earned-item timestamps and keepsakes are preserved; catalog availability
requires no database migration or growth calculation. The existing diagnostic
`unlockedAt` field remains for compatibility: universally available entries
without historical rows use zero. It no longer implies an XP requirement.

The catalog retains historical happy-wiggle, sulk, hop and big-dance identifiers
for compatibility. They have no XP prerequisites. Their presence is not a claim
that every identifier has a distinct selectable implementation: existing motion
works at every level, and any future variants must also be independent of XP.
The current Waveshare board has no speaker.

For reference, cumulative XP milestones are:

| Level | Total XP |
| --- | ---: |
| 1 | 0 |
| 2 | 150 |
| 3 | 400 |
| 5 | 1,200 |
| 8 | 3,150 |
| 10 | 4,950 |
| 15 | 11,200 |
| 20 | 19,950 |
| 30 | 44,950 |

These milestones grant no functionality or cosmetic reward. A level-up visual
can acknowledge the statistic without granting an ability.

## Milestone keepsakes

These are permanent inventory records awarded independently of level:

| Keepsake | Trigger |
| --- | --- |
| First dance | A dance-sized celebration is recorded |
| 100th task | Recorded task count reaches 100 |
| 30-day streak | Best streak reaches 30 active days |
| First late night | A late-night moment is recorded |

Keepsakes do not have an additional XP award in the current formula. Their
underlying activity may independently earn XP.

## Streaks and rest days

A streak counts active local days. Every seven lifetime active days banks one
rest day, up to three. Each missed day consumes a banked rest day before the
streak breaks. Protected rest days preserve the streak but do not increment it
or earn an active-day award. Today is not considered missed until tomorrow.

An unprotected missed day resets the current streak only: lifetime XP, levels,
appearance choices and best streak remain. The daily bonus grows with the current
streak and stops increasing at +10 XP.

## Related systems

- **Bond:** a separate, hidden relationship value; not spendable XP or a skill
  point balance. Its intended behavior is described in `UX-GROWTH.md`.
- **Traits:** personality axes are separate from XP.
- **Leaderboard:** optional sharing/ranking of progress uses device signatures.
  A signature authenticates the signed payload; it is not independent evidence
  that every underlying coding event represented meaningful work.
- **Celebrations:** hop/cheer/dance selection reflects the completed work, not
  the pet's level. Level-up presentation is a separate visual event.

## Open product decisions

1. Tune awards and thresholds against real usage: how many ordinary coding days
   should each milestone take? No target leveling pace has been validated yet.
2. Keep behavior and appearance independent of XP; no skill tree is planned.
3. Decide whether historical animation/expression/sound catalog identifiers need
   distinct presentations or can be retired; they are not progression rewards.
4. Review task/session farming limits and best-effort token weighting before
   treating public rankings as a competitive system.

## Implementation references

- [Growth.swift](../app/Boop/Core/Store/Growth.swift): award values, caps, level
  formula, streak arithmetic and universally available catalog.
- [Store.swift](../app/Boop/Core/Store/Store.swift): persistent awards, inventory,
  keepsakes and known-option checks when equipping.
- [BuddyReducer.swift](../app/Boop/Core/BuddyReducer.swift): activity-to-award events
  and celebration selection.
- [Heartbeat.swift](../app/Boop/Outputs/ESP32/Heartbeat.swift): progress projection
  sent to the physical device.

Update this document with `UX-GROWTH.md` when tuning progression. Catalog entries
are not proof of end-to-end verified presentation.
