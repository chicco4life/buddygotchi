# UX: Model-driven buddy behavior

Owner simplification: keep event-based dialogue and evidence-backed memory.
Remove periodic check-ins, numeric traits/bond and daily trait adjustment.

## Steering and responsibility

The bundled [BEHAVIOR.md](../app/Boop/Resources/BEHAVIOR.md) defines personality.
Settings → Edit buddy behavior… creates/opens `~/.boop/BEHAVIOR.md` (or inside
BOOP_STATE_DIR) without overwriting edits. Every decision rereads it. Missing,
empty, unreadable, invalid UTF-8 or over-32-KiB overrides use the bundled guide.
Owner configuration is trusted; runtime context is data.

Rules own state, effort, celebrations, XP and attention reminders. The model
chooses dialogue/silence and supported profile memories. It has no tools or
permission authority. Approvals remain in the editor.

## Dialogue

Offer a decision on return greeting, explicit error, or when a completed turn's
celebration finishes and Buddy returns to idle. There are no timed check-ins.
Sub-minute work does not celebrate, so it has no post-celebration remark.
Greeting animations retain their existing time-away levels.

Context includes state, sessions, effort, completed-task duration, time/language,
known agent, growth, at most five recent factual outcomes/durations/dates, three
profile lines and twenty prior dialogue lines. No numeric personality traits,
bond, usual-hour inference, project/session familiarity counters, historical
moments, raw paths, transcripts or tool arguments.

A line or SILENT is valid. Bubbles last four seconds, are at most 63 UTF-8 bytes,
and never cover attention requests or wake Buddy. Cancel/discard stale replies
after state/card/language/runtime changes, replacement or shutdown. Completion
text cannot delay, resize, cover or restart a celebration. Code validates
language, control characters, character-safe length and exact repeats; it does
not prove semantic truth. Quiet mode changes sound only.

## Runtime

Apple Foundation Models on supported macOS 26+ runs locally, with fresh sessions,
temperature 0.4 and a five-second async deadline. No cloud fallback or bundled
alternate model. Separate device/profile lanes keep reflection independent.
Unavailable/invalid responses produce one neutral greeting/error line when not
already used, otherwise silence. Reflection failure leaves the profile unchanged.

## Private memory learning

Once per day after twenty inactive minutes on AC power, reflect on evidence up
to the previous day. Reduced facts expire after 30 days. The model receives at
most 100 facts and twenty existing profile lines, with no approval decisions or
raw identifiers. Return SILENT or `{"memories":[{"line":"…","evidence":[0]}]}`.

At most five new memories per update, each at most 240 UTF-8 bytes and citing
valid supplied evidence IDs. Invalid memory output rejects the update; successful
reflection is idempotent per local day. Old trait fields are ignored, never
applied. No numeric energy, cheek, warmth, curiosity or bond updates remain.
Legacy values stay stored but inactive. The guide selects useful supported
preferences rather than daily recaps. Profile lines remain inspectable/deletable.
