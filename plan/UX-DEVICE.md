# UX: ESP32 device

Supported hardware: **Waveshare ESP32-S3-Touch-AMOLED-1.64**, a 456×280 landscape
AMOLED with touch and motion sensing. The current board has no speaker.
[How Boop behaves](BEHAVIORS.md) owns shared state, timing, XP and model triggers;
this page owns the device's presentation and controls.

## Face and states

Two eyes and a mouth on black. No torso or legs. Arms appear for the greeting
wave and larger celebrations, retract afterward, and stay hidden behind cards.
Appearance is fixed. Small gaze, blink, lean and breathing motions carry expression.

| State | Face and field |
| --- | --- |
| Asleep | Closed eyes, slow breath, dim ink |
| Idle | Open eyes, drifting gaze and gentle bob |
| Working | Reading gaze; hard effort adds brow/sweat, grinding adds a small tremble |
| Needs you | Wide eyes, forward lean, amber field and request footer |
| Done | Arc eyes and smile; hop, cheer or dance in the completion notice |
| Uh-oh | Lowered gaze, slump and red breathing field |

On a connected calm screen, any working/thinking session keeps the working face;
otherwise it is idle. Attention, errors and sleep still win. Device completion
notices temporarily cover that face; their 5-second/8-second rules are in
[Celebrations](BEHAVIORS.md#3-effort-and-celebrations).

## What appears on screen

| Surface | Content |
| --- | --- |
| Calm face | Optional two-line scope above; working count and “tap for threads” below when work is live |
| Request | Borderless lower footer: tool, queue count, up to two lines of supplied reason; face lifts above it |
| Completion | Smaller cheerful face, agent and large thread title, latest second title when present, total count, sage wash |
| Thread/history pages | Three rows per page, with agent, status/title and navigation |
| Temporary remark | Plain text beside a smaller face, no speech-bubble box; up to 4 seconds or dismissal |
| Travel stats | Last synced personal progress, with the face beside it |
| System card | Pairing code or firmware-update information |

There is **no persistent Last finished row** and no separate bottom shortcut.
Recent completions remain in history. Scope is quiet and persistent until changed;
cards, errors, stats, details, completion, remarks, affection, sleep, nap and
lost connection hide it. Unchanged scope does not animate or restart a timer.

**Screen priority, highest first:** display off → system card → request card →
error remark → stats → thread pages → completion notice → ordinary remark →
greeting/affection → face. Base state still controls the expression and field.
System cards cancel completion notices and close details. Higher-priority work
never queues old completion notices to replay later.

## Touch and buttons

“Primary” means the board's BOOT button or an attached IO1 button. Secondary
means an attached IO2 button; IO5 is an alias. The bare board does not have all
three external buttons. These names describe controls, not approve/deny actions.

| Context or gesture | Result |
| --- | --- |
| Tap while screen is off or face-down napping | Wake only; consume that tap |
| Tap screen or primary with a passive request visible | Hide that card locally and suppress reminders for its ID; request stays pending |
| Tap a system card | Does not dismiss it as a passive request |
| Tap screen/primary with a temporary remark visible | Clear the remark before any normal face action |
| Tap the calm face with live work or recent completions | Open the first thread/history page |
| Tap the calm face without work/history | Boop: squish, smile and an occasional heart |
| In detail pages: bottom-right Next | Advance one page, wrapping to the first |
| In detail pages: any other tap, primary or secondary short press | Return directly to the face; hidden dialogue cannot consume the exit |
| Hold primary for 1 second, without a card | Pet; continues affection while held |
| Double-tap primary in travel posture | Open/cycle stats; outside travel, use the normal primary action |
| Secondary short press | Close details, dismiss passive card or clear remark first; otherwise cycle stats in travel/while stats are open, or give a small head shake |
| Hold secondary for 1 second | Toggle Quiet mode |
| Continue secondary hold to 3 seconds | Show “night night”; screen turns off on release or at 3.6 seconds |

A long secondary hold passes through the Quiet toggle on the way to screen-off.
It turns off the display, not the agent or Mac app. A new request/system card
can wake the display. Touch and motion never answer an editor request.

Details start with current sessions, then recent completions. Next appears only
with multiple pages; Back stays visible. Rows keep stable order as status changes.
The preview holds up to 12 sessions and 6 completions, sometimes fewer to fit the
wire budget; totals and omitted-row counts expose the limit. Idle chats imply no
unread obligation. Prefer supplied titles, otherwise project plus a short stable
ID; never use raw prompts/commands as titles. See [Wire](WIRE-V2.md) for byte bounds.

## Affection, greeting and motion

| Moment | Motion |
| --- | --- |
| Boop/pet | Squish and smile; one heart floats up off the left cheek, no boop blush. At most one heart per 2.5 seconds; holding adds no stream of hearts |
| Return after 18 hours away | Short greeting, blink/smile and right-arm wave |
| Return after 7 days away | Warmer greeting with bounces and one heart; no penalty for time away |
| Hop | One bounce, no confetti |
| Cheer | Two bounces, small head wag and raised arms |
| Dance | Bounce/sway with raised arms and at most five fading confetti dots |
| Idle | Occasional yawn, gaze sweep, wiggle or head tilt; 1.8 seconds, spaced 120 seconds on desk/perch or 90 in travel, at least 10 seconds after input |
| Shake | Small-eye wobble for 3 seconds |
| Pick up | Wide-eye perk for 1 second |
| Face down for 2 seconds | Nap; turn face up for 0.7 seconds to leave it |
| Streak reaches 7, 30 or 100 in a new snapshot | Brief streak visual; no XP bonus or level-up |

Cards suppress shake, pickup and face-down nap. Sleeping boops get a one-eye
peek rather than hearts. Greeting is caused by recorded activity after time away,
not every Bluetooth reconnect; the device wave runs for about 2.2 seconds.

Desk is the default posture; a stable tilt selects perch and changes gaze/lean.
Motion, or over a minute without live data while on battery, selects travel.
A candidate posture must hold for 2.5 seconds; ambiguous orientation retains the
previous one. There are no perch feet or body. Travel shows a battery mark below 25%.

Travel stats auto-hide after 10 seconds. Page one shows name, streak and cumulative
XP; page two shows days together, completed turns, biggest cheer and today's turns.
These are last synced values, not a live offline work counter.

## Connection, brightness and sound

A first wake starts grey and gains its normal appearance on the first host signal.
The Bluetooth glyph pulses while unpaired or without live data, and briefly lights
solid on first frame/reconnection. A frame remains live for up to 60 seconds;
after live data expires, a further 10-second face grace precedes idle fallback.
Stale cards, dialogue and details clear on data loss. Reconnect restores current
host state without replaying completion history.

| Display condition | Brightness, out of 255 |
| --- | --- |
| Visible card | 255 |
| Awake, recently active | 210 |
| No input or relevant state/cheer change for 2 minutes | 90 |
| Asleep or face-down nap | 28 |
| Explicit screen-off gesture | 0 |

Automatic inactivity does not turn the display fully off. A visible request does
not dim. **An unchanged working state can dim**: repeated keepalives and cosmetic
changes do not reset inactivity. This corrects the former documentation claim
that working could never dim; the table describes the current implementation.

The firmware schedules authored request, nudge, completion, greeting, error and
boop motifs. Quiet mode mutes all of them, preserving every visual/timer. Normal
volume is fixed at step 1; motifs are spaced at least 1 second, completion sounds
at least 10 seconds. This board's sound output is a no-op.

## Rendering rules and verification

Warm cream ink on black; amber means attention, sage completion and rose affection.
Colours must remain distinct through the actual RGB565-to-RGB332 rendering path.
In particular, amber and red field washes must not collapse into the same colour.
Constants live in [palette.h](../firmware/esp32/firmware/palette.h).

Text is UTF-8 safe and uses the bundled Korean-capable font. Scope has 24 px side
margins; details use 40 px sides and 24 px top/bottom, with three inset rows. The
request footer is 88 px high, with aligned labels and a top hairline.

Arrivals spring; departures retract smoothly. Interrupted head tilt eases back,
and retracting arms keep their last angle rather than flipping down. Departing
card text follows its card, accepts no input and cannot cover a higher-priority
surface. Completion wash fades in over 250 ms and out over 600 ms. Frozen-clock
settled poses remain deterministic for screenshots.

Use [verification](VERIFICATION.md) and [current status](PLAN.md) for measured
results and remaining gates. USB debug tests require restoration to normal
firmware; they do not prove production Bluetooth. Webcam review requires explicit
setup for that session. Retired concepts live in [device history](UX-DEVICE-HISTORY.md).
