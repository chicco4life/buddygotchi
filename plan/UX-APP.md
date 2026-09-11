# UX: The Mac app

The hardware is the companion. The Mac app runs quietly in the background as
its status and configuration surface. Normal use should not require opening it.

## App behavior

- Launch as a menu bar accessory: no Dock icon, startup window, or automatic
  onboarding. A first-run setup link appears when the person opens the menu.
- A static monochrome status icon has a filled variant when an agent needs you.
  No animation, XP counter, or completion celebration in the menu bar.
- Clicking opens a native transient popover anchored to the icon. Clicking again,
  outside, or pressing Escape closes it. Opening normally returns to Overview.
- State changes never open or close it, including attention requests. Old
  interactive-mode preferences are ignored. Previously opted-in passive
  notifications remain available; selecting one opens the dropdown.
- Settings and setup are reached inside the same dropdown,
  with Back navigation. Secondary confirmation and utility sheets remain attached.
- No creature or animated face in ordinary app content or setup. The physical device owns Buddy's expression.

## Overview

One column, 360 pt wide, with system typography, native controls and whitespace.
No sidebar or top-level tab strip.

**Palette (2026-09-11).** The app no longer inherits the system semantic
colors. It uses "Boop Cream", hand-authored for both appearances in
`app/Boop/Theme/BuddyTheme.swift`: warm paper (`#FAF7F2` / `#1B1815`),
warm ink (`#24211C` / `#F2EBE0`), one terracotta accent (`#D97757`), and
three semantic tones — amber for needs you, sage for done, rose for
affection. The device shares that trio and inverts the field, so a colour
means the same thing on both screens (see `plan/UX-DEVICE.md` §7).
Terracotta marks every primary action, selection and progress indicator;
**amber is reserved for "an agent needs you" and never marks an action.**
The trade this accepts: owning both appearances costs the free system
behaviours (increase-contrast, tinted appearances), so every `*Ink` tone
is hand-checked to clear 4.5:1 against its own appearance's paper, and
the `*Faint` tones are decoration and disabled affordances only.

**Structure (2026-09-11).** Sections are a small tracked-out label above a
card, not rules between blocks: space and the label separate them, which
keeps a 360 pt column from reading as a form. A status line opens with a
tone dot that breathes only while work is actually live. Session rows are
cards carrying their tone in a 3 pt leading bar rather than in the text,
so ten rows do not become ten coloured sentences. Progress is three stat
tiles over the grid. Device battery is a small drawn pip, amber under 25%,
matching the device's own low-battery mark.

1. Buddy name. No level label.
2. Current state and a short explanation: Working, Idle, Sleeping, Needs you,
   Done, or Needs attention. Device connection is independent of agent state.
3. Pending requests appear only on Overview, below its status. Settings
   and setup display only their own content, even while attention is pending.
   Show the tool, supplied reason (or tool name), queue position and
   “Check your editor”. There are no stakes or Approve/Deny buttons.
4. All sessions appear immediately after status and any pending request, with
   agent, project when known, and status. The dropdown grows for up to ten sessions;
   additional sessions remain scrollable. Empty state: No agents awake.
5. Device connection and battery percentage when connected and known. Missing
   battery is omitted; never substitute a made-up percentage.
6. XP is the last content section: cumulative XP, completed turns and current
   streak in one row, followed by a compact twelve-week daily completed-turn grid.
   No level, target or progress bar. The grid has no title; “Last 12 weeks” sits
   below it, with a less/more legend on the same line. Cells are 15 pt squares
   on the sage scale; an empty day is a warm well rather than a grey, which on
   cream reads as "nothing yet" instead of as a hole. Today carries a terracotta
   ring. Hover a square for its date and exact count.
7. Plain Settings button at the bottom-left and Quit at the bottom-right. No overflow menu or share-card export.
   There is no Activity button or pane.

Overview retains progress and statistics while idle or sleeping. It uses a
548 pt base viewport (692 pt with a pending request), growing by 46 pt per
additional session beyond one, up to ten and bounded by available screen height;
secondary panes use 560 pt. The base grew with the cards and the larger
activity cells: at 440 pt the twelve-week grid and its legend were clipped.
Long content scrolls inside the dropdown.

## Settings

Settings is one continuous scrollable form. Every group is expanded and visible
in the same view; there is no category picker, sidebar, or extra profile page.
Simple headings separate:

- Buddy & sound: name, language, and Quiet mode.
- Device: connection, pairing, and firmware.
- Agents: installation status, connect and repair actions.
- General: launch at login.
- What your buddy knows: inspect and clear stored profile lines inline; “Edit buddy behavior…” opens the Markdown guide for event-based dialogue, personality and memory.
- Support: Report a bug saves a diagnostic file for sharing with support.
- About: version, Check for updates, and Help & support.

Written dialogue is automatic, with a neutral greeting/error fallback and
otherwise silence when the local model is unavailable. There is no Voice picker. Sound uses fixed volume step 1; Quiet
mode is the only sound control. Appearance is fixed to the default skin,
no accessory, and default silhouette. Old saved choices remain stored but are
inactive. Quick command, Reset, and Retire buddy are removed from Settings;
no existing progress is erased. Ordinary action buttons use plain styling to
avoid dark filled rectangles within the form.

## Quiet mode

Quiet mode turns off **all sounds and beeps**, with no high-stakes exceptions.
Animations, expressions, visual attention reminders, nudge timing, state changes,
XP, and agent behavior remain identical. It neither approves nor denies requests.

The setting lives in Buddy & sound, labeled "Quiet mode", with the description
"Turn off Buddy’s sounds. Screen behavior stays the same." Turning it off restores
the fixed default volume (step 1). The physical button's former Focus gesture controls the same
setting. No Focus hours or scheduled behavior remain; old schedule values are
ignored. The existing sounds-enabled preference is retained so existing mute
choices survive upgrades and restarts. Wire names remain compatible; see WIRE-V2.

English and Korean copy are supported. Review both system appearances.

## Approvals and reminders

Approvals belong entirely to the editor. Buddy interception and both opt-in
settings are removed. Stale hooks return immediately to native approval.
Passive attention remains on Overview. “Snooze reminder” suppresses that request's
60/120-second nudges without resolving it; the next request starts fresh.

Firmware check errors read “Check unavailable”; the sheet shows the underlying
error and offers Try again. This is separate from an installation failure.
