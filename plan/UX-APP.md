# UX: The Mac App

Status: first draft, 2026-09-09, written by the agent to unblock Phase 7;
layout decisions are assumptions. Refines `VISION.md` §7 and `UX-DEVICE.md`
Part I for the desktop side.

## Surfaces

1. **Menu bar creature.** The status item is the creature's face at 18 pt:
   the same six states and three cheer sizes as the device, in the same
   vocabulary. Tooltip: state and parameter.
2. **Popover** (one column, cream palette): the creature large at top with
   the state pill; the needs-you card when present (tool, gloss, stakes dot,
   Deny and Approve); the per-session list with each session's state, tool,
   and its own cheer or moment; the gift orb with the story line; a footer
   with connection, level and streak ("L4 · 3d"), and the gear.
3. **Onboarding** (window, five steps): welcome with the sleeping buddy;
   connect agents (per-agent rows with a "heard from" moment); pair the
   device (or "later"); name the buddy (permanent); the first cheer.
4. **Recap** (popover section at end of day, and a menu item): one paragraph
   in the buddy's voice plus a three-line tally (turns, tasks, biggest).
5. **What your buddy knows** (window): the profile lines with source and
   date, delete per line, clear all with a confirmation that explains name,
   level, and bond are kept.
6. **Settings** (window): agents and hook repair, device, sounds and volume,
   focus hours, language, leaderboard opt-in (Phase 8), quick command
   text, retire.

## Interactions

- Approve and Deny mirror the device exactly; whichever side decides first
  wins.
- Clicking the orb collects it.
- Focus toggle in the popover header.
- Every string keyed for localization; English and Korean.

## Doctrine on the desktop

Premium and quiet: no badges, no counters in the menu bar, no notifications
except needs-you when the popover is closed and the user opted in.
