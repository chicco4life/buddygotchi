# UX: The Mac App

Status: revised 2026-09-09 after the owner's UI review. Refines
`VISION.md` §7 and `UX-DEVICE.md` Part I for the desktop side.

## Visual language

**Native macOS.** The app uses system materials and controls: the
popover is a standard `NSPopover` with the system material background,
type is the system font at the standard text styles, controls are
standard SwiftUI controls, icons are SF Symbols, colours are the semantic
system colours plus one accent. The accent is the buddy's amber
(`BuddyPalette.amber`), used for the primary action and the needs-you
state only. Green and red are the system colours for done and uh-oh.

The creature itself keeps its own look: eyes and mouth on a black
rounded field, matching the device pixel for pixel (no body shape;
`UX-DEVICE.md` §7). It is the only branded element on screen.

Rules: no custom card chrome (borders, tinted boxes) around content; use
grouping and whitespace. One accent. One type scale. No text in monospace
outside the quick-command field. Every string comes from the copy table
(`BuddyCopy`), never an enum name or internal tag.

## Surfaces

1. **Menu bar creature.** The status item is the creature's face at 18 pt:
   the same six states and three cheer sizes as the device. Tooltip: state
   and parameter.
2. **Popover** (one column, 360 pt wide):
   - Header: buddy name (headline), state as a short secondary label
     ("needs you", "working", "asleep"), gear at the right.
   - Creature: the black field, 160 pt tall, corner radius 20.
   - Needs-you card, when present: tool (headline), gloss (body), a
     stakes dot with the stakes word in secondary text, Deny (plain) and
     Approve (prominent, accent). No border; a grouped background.
   - Sessions: one line per session (agent icon, label, state), only when
     more than one agent is awake. When none: a single secondary line
     "No agents awake" with no box.
   - Gift: the gold orb with the story line, inline, tappable.
   - Recap, when available: one paragraph in the buddy's voice and a
     three-line tally with human labels (`Turns`, `Tasks`, `Biggest
     moment`, whose value is the moment's phrase, e.g. "a hard-won pass",
     never the enum).
   - Footer: level and streak as a short secondary label ("Level 4 · 3-day
     streak"), a Focus toggle (bordered, small), and the device dot only
     when a device is paired. Nothing else.
3. **Onboarding** (window, five steps): welcome with the sleeping buddy;
   connect agents (per-agent rows with a "heard from" moment); pair the
   device (or "later"); name the buddy (permanent); the first cheer.
   System window background, large title, standard buttons.
4. **Recap** (popover section at end of day, and a menu item).
5. **What your buddy knows** (window): a plain list with the sentence and
   a secondary date; hover reveals a delete; a footer "Forget everything"
   with a confirmation that explains name, level, and bond are kept. No
   source tags.
6. **Settings** (window, five sidebar sections, standard `Form` grouping):
   - **Buddy**: name, language, voice, sounds and volume.
   - **Agents**: one row per agent with state and a Repair or Connect
     button.
   - **Device**: pair or forget, firmware, retire (destructive, at the
     bottom, with confirmation).
   - **Focus**: focus hours, interactive mode, launch at login.
   - **Advanced**: local approval mode, quick command, leaderboard opt-in
     with URL and friends, agent drawings, diagnostics export, remove Boop.

## Interactions

- Approve and Deny mirror the device exactly; whichever side decides first
  wins.
- Clicking the orb collects it.
- Focus toggle in the popover footer.
- Every string keyed for localization; English and Korean.

## Doctrine on the desktop

Premium and quiet: no badges, no counters in the menu bar, no
notifications except needs-you when the popover is closed and the user
opted in. Feels like part of the Mac, with one small creature living in
it.
