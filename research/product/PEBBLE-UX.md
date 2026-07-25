# Boop Pebble UX Spec — Face-First Redesign

Status: approved direction (2026-07-25), end-state behavior spec for implementation
Applies to: `ws-amoled164` firmware (Waveshare ESP32-S3 Touch AMOLED 1.64, landscape 456×280)
Companion docs: `PRODUCT.md` §10 (Blob interaction design — the ancestor of this spec),
`research/eng/waveshare-amoled-port.md` (hardware + current firmware state),
`research/eng/one-creature-review.md` (what the 2026-07-22 pass shipped, with by-hand
test steps), `firmware/esp32/PROTOCOL.md` (the wire contract)

This spec describes the **end behavior** of the polished Pebble product. It supersedes
the current HUD-based resting screen. The M5StickC portrait renderer is untouched —
everything here lives behind `HAL_LANDSCAPE` / board guards.

> **Reconciled 2026-07-25 against the "one creature" pass** (main @ `2bab063`,
> reviewed in `research/eng/one-creature-review.md`). That pass shipped and
> hardware-verified a meaningful slice of this spec ahead of it: the QMI8658 IMU is
> wired, touch is real petting, and boops now round-trip to the desktop as a `heart`
> pet state. Sections below marked **[shipped]** describe behavior that already exists
> — verify and extend it, do not rebuild it. §15 marks the affected build steps.

---

## 0. Hardware facts that shape the design

- **No speaker, no LED.** `halTone`/`halSetLed` are no-ops on this board. **The screen
  carries the entire ambient/emotional channel.** Sound is explicitly out of scope for
  v1 (decision 2026-07-25): all feedback is visual. A future speaker is a hardware
  question tracked in PRODUCT.md; nothing in this spec depends on audio. (Chirp calls
  elsewhere in the firmware — the dizzy chirp, approve/deny chirps — are live on the
  M5 and silently no-op here; that's fine, leave them.)
- **Three buttons:** top crown ("boop", IO1), bottom-left ("look", IO5),
  bottom-right ("no", IO2). BOOT doubles as boop until soldering. Pins are live in the
  HAL already — soldering needs zero firmware change. Power-down wake is BOOT-only
  until IO1 exists as a non-strap wake source.
- **Touch (FT3168)** — affection-only, by doctrine. **[shipped]** as real petting
  (§10.1); health via `halTouchReady()`, self-healing 2s re-probe.
- **IMU (QMI8658C, 0x6A/0x6B on the touch I2C bus)** — **[shipped]**: ±4g @125Hz,
  polled 20Hz, `halImuRead()`, health via `halImuReady()` with 5s re-probe and 500ms
  error backoff. Face-down nap and shake-dizzy detectors live in `motionTick()`
  (§10.2). Pick-up is the one gesture still unbuilt.
- **AMOLED on true black** — black pixels are free (power + burn-in), glow is cheap.
- Render pipeline: 8bpp RGB332 sprite in PSRAM, 456×280 native, per-frame
  damped-exponential easing, 24ms present cadence. Fluid animation is already paid for.
- **The wire contract is no longer read-only.** The device already sends
  `{"cmd":"permission"}`, `{"cmd":"species"}`, and `{"cmd":"boop"}` upstream, and
  consumes a `heart` pet state coming back. Additions are therefore a normal,
  precedented move — not the boundary violation an earlier draft of this spec assumed.

---

## 1. Doctrine (hard rules, never break)

1. **At rest the screen is 100% face on black.** No status text, no labels, no counters.
2. **Field brightness encodes need (§2.1).** Black = nothing needed, dim warm = something's
   off, light = act now. A light field is spent *only* on states where a human is
   blocking something; spending it on happy states destroys its meaning.
3. **Three information tiers:**
   - *Ambient* — expressed through behavior (face, halo, orbs), never text.
   - *Summoned* — shown on request (glance card), auto-dismisses.
   - *Demanded* — takes the screen (approval, error, OTA, passkey) and only these may.
4. **Buttons are the only actuators.** Touch and IMU are affection/display-only and can
   never approve, deny, or change persisted state. (Existing doctrine — keep.)
5. **Approval safety is untouched:** 600ms prompt-arming delay, wake-press guard on
   both boop and reject, decision requires a mechanical press.
6. **Nothing teleports.** Every visual state change is a transition (crossfade/ease
   ≥150ms, spring where playful). No hard fillRect swaps between modes.
7. **Nothing blocks.** All animation is per-frame incremental; no delay()-paced
   sequences.
8. **Everything breathes.** No fully static frame while the screen is on: idle bob,
   halo breath, orb drift. (Doubles as burn-in insurance with the pixel drift.)
9. **Text is a last resort** — only inside bubbles/cards, never bare on the face.
10. **Physics over keyframes** for touch/motion-driven motion (squish, dangle, wobble):
    spring simulations, not sprite sequences.
11. **Visual-only.** No chirps/beeps on this board in v1.
12. **Urgency beats affection.** **[shipped]** — the `heart` state overlays calm states
    only; attention, error, and sleep always win. Booping during a pending prompt does
    not produce hearts, and motion gestures (shake, nap) are suppressed while a prompt
    is armed. Affection may never obscure or delay a decision the human owes.

---

## 2. Screen priority stack

Highest wins; lower layers keep simulating (springs settle, orbs drift) so nothing
snaps when an overlay clears.

| Priority | Mode | Notes |
|---|---|---|
| 1 | OTA progress | Full takeover (unchanged); Night mood |
| 2 | BLE passkey | Full takeover (unchanged); **Lantern** mood — the code must be read and typed now |
| 3 | Approval card | Face persists, **Lantern** mood + card overlay (§7) |
| 4 | Decision feedback | "yes!" / "okay" until desktop clears prompt (unchanged behavior, restyled as bubble) |
| 5 | Menu carousel | Unchanged grammar (look-hold opens; MENU=next / BOOP=pick / REJECT=back) |
| 6 | Glance card | §6; dismissed by any higher layer |
| 7 | Heart / affection overlay | **[shipped]** §4; overlays calm states only — never outranks 1–4 (doctrine #12) |
| 8 | Face + halo + orbs | The resting product |

Orthogonal: dim/off ladder (§9) and sleep state. A pending prompt always wakes and
never dims (existing rule — keep).

### 2.1 Screen moods — the field is the alert channel

The most legible signal a screen can send across a room is **overall luminance**, not
color or shape. So the background field is promoted from a constant to the product's
primary alert channel, with one rule:

> **Field brightness encodes how much the buddy needs you.**
> Black = nothing needed. Dim warm = something's off. Light = act now.

Three moods, pre-attentively distinguishable with zero reading:

| Mood | Field | Face | Used by |
|---|---|---|---|
| **Night** (default) | true black | glow-on-black (existing) | idle, busy, thinking, sleep, celebrate, gift-waiting, glance card, menu, OTA |
| **Ember** | deep warm brown, barely lifted from black | dim red heartbeat | error / dizzy |
| **Lantern** | warm cream, full field | **inverted: dark ink on cream** | approval prompt, BLE passkey |

Lantern is a genuine luminance inversion — the whole panel flips dark→light. Nothing
else in the product does this, which is what makes it unmissable in peripheral vision.
It is also rare and transient (seconds, only when a human is blocking something), so
the usual AMOLED objections — power, burn-in — don't apply; §2.1.4 caps exposure anyway.

The physical payoff: **at night the device becomes a small warm lamp and visibly
changes the color of the desk around it.** This is the "desk halo" the Blob concept
wanted external LEDs for (PRODUCT.md §9.3), delivered free by the panel we already
have. Worth filming for the landing page.

Reserving light strictly for "act now" is what keeps it powerful — which is why the
glance card, gift-waiting, and celebrate all stay in Night mode even though they're
visually eventful. Spending the lantern on happy states would cost it its meaning.

#### 2.1.1 Exact palette (RGB332-reachable)

The 8bpp canvas quantizes to RGB332 (`_buildLut()`, `hal_ws_amoled164.cpp:61`): red
and green have 8 levels each, **blue has only 4** (0, 82, 173, 255). Neutral
off-whites are therefore unreachable — but warm creams are, which suits the brand.
All values below are exact RGB332 lattice points, so they render with zero
quantization error:

| Token | RGB | Hex | Role |
|---|---|---|---|
| `FIELD_LANTERN` | (255, 219, 173) | `#FFDBAD` | warm apricot cream — base alert field |
| `FIELD_LANTERN_HOT` | (255, 182, 82) | `#FFB652` | escalated amber (§2.1.3) |
| `FIELD_EMBER` | (74, 36, 0) | `#4A2400` | deep ember brown |
| `INK` | (33, 0, 0) | `#210000` | warm near-black — face + primary text on lantern |
| `INK_DIM` | (107, 36, 0) | `#6B2400` | secondary text / rules on lantern |

Two techniques if a tone needs finer tuning than the lattice allows:

- **Ordered dither on flat fields.** A 2×2 dither between adjacent lattice points
  (e.g. blue 173↔255) is invisible at 340 PPI and yields intermediate creams such as
  `#FFEBD0`. Flat fields don't band — banding is a gradient problem — so dithering
  here is for tone selection, not smoothness.
- **LUT overrides.** `_buildLut()` is ours; specific RGB332 codes can be remapped to
  exact RGB565 brand values in ~3 lines, giving pixel-perfect mood tones. Cost: those
  codes shift globally, so reserve them to the mood system only.

#### 2.1.2 Rendering the inverted face

Dark-ink-on-cream is not merely recolored glow-on-black; two adjustments are required:

- **Thin strokes by ~10%.** Light shapes on dark fields optically expand (halation);
  dark shapes on light fields don't. Reusing glow geometry unchanged makes the ink
  face read heavy and clumsy. `face.h` needs a weight factor keyed to mood.
- **Anti-aliasing gets *better*.** The existing `fillSmoothRoundRect`/`fillSmoothCircle`
  calls have no bloom to fight on a light field, so at 340 PPI the ink face reads as a
  crisp printed illustration. This is an upgrade, not a compromise — the creature
  "steps into the light" to ask its question.
- Cheap and elegant: a ~6px cream margin outside a thin `INK_DIM` rule framing the
  card, for a matted-print quality.

#### 2.1.3 Transitions — bloom and snuff

Mood changes are the most visible motion the device makes, so they get the most care.
Nothing snaps (doctrine #6).

- **Bloom in (→ lantern), ~350ms ease-out:** a radial light front expands from
  *behind the face* outward past the screen corners, filling `FIELD_LANTERN` as it
  goes; the face crossfades glow→ink across the same window (3–4 steps suffice). Reads
  as a lamp warming — and as the buddy lighting itself up to ask.
- **Escalation (unanswered ≥10s):** field warms `FIELD_LANTERN` → `FIELD_LANTERN_HOT`
  over ~2s and the field-luminance breath quickens (4s → 1.2s period, ±6%). This *is*
  the urgency signal — it replaces the numeric `waiting Ns` counter entirely. Field
  motion is detected peripherally even better than hue.
- **Snuff (approve), ~250ms:** green ripple, then the light **contracts back into the
  face** and goes out — the buddy swallowing the light. Deliberately faster than the
  bloom; resolution should feel decisive.
- **Fade (deny), ~350ms:** field dims evenly to black. No ripple, no contraction.
  Neutral and unhurried — denial is responsible, not punished.
- **Ember in/out, ~500ms:** slow crossfade both ways. Errors are not startling.

#### 2.1.4 Brightness, decay, and safety

- **Night-aware entry.** If the screen was dimmed or off when the prompt arrived, the
  lantern blooms to a reduced peak (~60%) and ramps to full only as it escalates.
  Waking a dark room with a full-brightness cream field is the one way this feature
  turns hostile.
- **Long-unanswered decay.** After **2 minutes** unanswered, the field decays from
  lantern toward ember, keeping a slow amber pulse at the top edge. Protects the
  panel, avoids lighting an empty room all night, stays honest (the prompt is still
  pending; the glance card still says so). Any input or decision restores full mood
  immediately.
- Panel brightness (DCS `0x51`) stays governed by the dim ladder; the mood system
  controls *content* luminance. The two multiply — keep them independent, don't drive
  `0x51` from mood.
- The existing 4-phase pixel drift applies to lantern and ember fields too.

---

## 3. The face layer (resting screen)

Full-bleed face (existing `face.h` eyes+mouth, per-species geometry, species accent
color), plus three new always-on elements:

### 3.1 Halo — the light language

A soft radial glow behind/around the face, centered slightly above screen center.
This is the Blob's LED language mapped onto the panel — the ambient channel **within
Night mode**. Attention and error are handled by the field instead (§2.1); the halo
fades out as a lantern bloom passes over it, so the two never fight for pixels.

| State | Halo | Period |
|---|---|---|
| idle | barely-there warm white, breathing | ~6s |
| busy/thinking | species accent color, slow breathing | ~4s |
| celebrate | one green→warm ripple outward, then gift twinkle (§8) | one-shot ~1.2s |
| sleep | none (black) | — |
| attention | — (Lantern field, §2.1) | — |
| error | — (Ember field, §2.1) | — |

Implementation notes (constraints, not choices): the canvas is RGB332 — smooth radial
gradients will band. Use an ordered-dither radial fill or a small set of concentric
smooth-edged rings at low intensity; keep peak brightness low (banding is invisible in
dim glow). Halo center drifts with the existing 4-phase pixel drift. Budget: the halo
redraw must fit the existing 24ms present cadence — precompute a radial distance LUT
at init if needed.

### 3.2 Orbs — sessions as fireflies

One orb per agent session, drifting slowly around the face perimeter (Lissajous-ish
paths, excluded from an ellipse around the eyes/mouth so the face stays readable).

| Session state (from heartbeat) | Orb |
|---|---|
| running | species accent, soft pulse |
| waiting on user | amber, brighter, gravitates to hover near an eye |
| done, uncollected (gift, §8) | gold, twinkling |

- Data source: `tama.sessionsRunning` / `sessionsWaiting` (already in the heartbeat) —
  counts, not identities; orbs are anonymous. No wire change.
- Spawn: fade+scale in over ~400ms; despawn: shrink+pop. Count changes animate one orb
  at a time (stagger ~150ms) so the sky never flickers.
- Cap at **6 rendered orbs**; beyond that the 6th renders slightly larger with a subtle
  double-pulse ("many"). Exact numbers live in the glance card.
- When a session starts, the face's gaze flicks toward the spawning orb for ~600ms
  (it *noticed*).

### 3.3 Gaze with meaning

Idle gaze is not random noise: priority order for gaze targets —
1. active touch point (§10), 2. newly spawned orb (600ms), 3. amber waiting orb
(periodic glances), 4. existing idle glance/drift behavior.
During a prompt the eyes look up at the crown (existing — keep).

---

## 4. State → behavior map

Driven by `tama.pet` exactly as today; this table is the end-state presentation.

| pet | Mood (§2.1) | Face (face.h) | Halo | Extras |
|---|---|---|---|---|
| sleep | Night | lids + z's | off | dim ladder §9; boop/touch → sleep-peek (existing) |
| idle | Night | blink/glance/bob | warm breath | micro-idles §12, orbs, gift twinkle if pending |
| busy | Night | half-lids + working dots | accent breath | busy theater §11 shows `activity` verb behavior |
| thinking (stall) | Night | drifting "…" | accent breath, slower | explicitly calm, not an alarm |
| attention | **Lantern** | wide eyes raised to crown, inverted to ink | — (field replaces it) | approval card §7 |
| celebrate | Night | arc eyes + confetti burst | green ripple | then gift-waiting §8 |
| heart **[shipped]** | Night | heart-eyes + pink blush + drifting mini-hearts | warm flutter | affection overlay, ~2.5s sliding window; calm states only (doctrine #12) |
| error/dizzy | **Ember** | X-eyes | red heartbeat | persists until booped → shake-it-off animation → idle |

`heart` is not a heartbeat-derived mood like the others — it is a **round-trip**: the
device boops → `{"cmd":"boop"}` upstream (rate-limited 1.5s) → the Mac reducer opens a
~2.5s `affectionUntil` window → the next heartbeat carries `pet:"heart"` back → the
device honors it as `P_HEART`. That mirror is what keeps the desk pet and the menu-bar
pet in lockstep. The device also flashes locally so affection never waits on the link.
Under Ember or Lantern, hearts are suppressed entirely (doctrine #12).

Note the halo (§3.1) and the field (§2.1) are complementary, not redundant: the halo
is the ambient channel *within* Night mode, and it yields to the field when the mood
changes — during a lantern bloom the halo fades out as the light front passes it, so
the two never fight for the same pixels.

Error acknowledgment: an error face stays (it's a *demanded*-tier fact) until the crown
is tapped — the buddy literally shakes it off (400ms head-shake spring), then returns
to whatever the heartbeat says. The boop only acknowledges the display; it sends
nothing upstream.

---

## 5. Button grammar

| Button | Tap | Hold |
|---|---|---|
| **Crown (top)** | context-affirmative: approve (armed prompt) → collect gift → acknowledge error → otherwise boop/squish | **two-stage ladder [shipped]**: 1.5s → screen off; keep holding to 4s → "night night" → power down |
| **Look (bottom-left)** | glance card; tap again while up → session detail pages | menu carousel (existing menu.h grammar) |
| **No (bottom-right)** | deny (armed prompt) → dismiss card/bubble → back (in menu) → otherwise a small "hmph" ear-flick (harmless) | — |

Crown tap resolution order (first match wins): armed prompt → pending gift → displayed
error → glance card open (dismiss + giggle) → plain boop. This keeps "crown = yes" a
single reliable verb.

**The crown hold ladder [shipped]** (`BTN_A_LONG_MS = 1500`, `BTN_A_DEEPSLEEP_MS =
4000` in `main.cpp`) supersedes the "sleep/wake toggle" this spec originally assumed.
It is a one-way ladder, not a toggle — waking is a *tap*, and the ladder is
deliberately staged so the destructive end (power-down) requires visible commitment.
Constraints worth preserving as this spec's features land around it:

- **Physical presses only.** Synthetic `press a --ms 5000` can never power down, so HIL
  can't strand the device; tests use `deepsleep <ms>` with a timer wake instead.
- **The wake-press guard eats taps, never holds** — so the ladder works from a dark
  screen, which is exactly when you want to power down. Any new wake-guard logic (§9.2,
  the pair-me bloom in §9.1) must preserve that distinction.
- On WS, power-down is **light sleep + `esp_restart`**, not true deep sleep: GPIO0 is a
  boot strap and a held wake button would strap the ROM into the serial downloader.
  Draw is ~1–2mA. Revisit once IO1 is soldered as a non-strap wake source.

---

## 6. Glance card (summoned tier)

The one place diagnostics live. Left-tap:

- **Motion:** card springs up from the bottom edge to ~55% screen height, face squishes
  up slightly to make room (it's presenting the card, not being covered by it).
  Overshoot ~6%, settle ~250ms.
- **Contents (page 1):** link glyph + word (`linked` / `link lost · 12m` /
  `connected, no data` / `unpaired`), sessions line
  (`3 sessions · 2 running · 1 waiting`), gifts pending count, battery %, firmware
  version + board name, species name. Chunky pixel font, `HAL_UI_SCALE`.
- **Page 2+ (left-tap again):** one page per known session summary if/when the
  heartbeat carries per-session lines; until then page 2 is the stats screen content
  (today's menu → stats). The buddy's eyes dart left as pages turn (it's "reading to
  you").
- **Dismiss:** auto-fade after 4s of no input (fade + slide down, 200ms); right button
  dismisses immediately; crown dismisses with a giggle; any demanded-tier event
  (prompt/error/OTA) dismisses instantly.
- While the card is up the halo and orbs keep animating behind it.

**Disconnected is not a word on the resting screen.** Link loss shows as behavior
(§9.1); the glance card is where the literal fact lives.

---

## 7. Approval card v2 (the hero flow)

The face never leaves the screen.

Sequence on prompt arrival:
1. Wake if dimmed/off (never approvable during the wake press — existing guard).
2. **Lantern bloom** (§2.1.3): the light front expands from behind the face, the field
   fills `FIELD_LANTERN`, and the face crossfades glow → ink over ~350ms. Night-aware
   peak if the screen was dark (§2.1.4). Face → attention: eyes wide, raised toward
   the crown. 600ms arming window starts (existing; presses that started pre-arm are
   swallowed).
3. A rounded **card** rises from the bottom edge (~40% height), drawn as ink on the
   cream field with an optional `INK_DIM` hairline rule: line 1 `source · tool`
   (`claude-code · Bash`) in `INK`, lines 2–3 word-wrapped hint (`git push --force`)
   in `INK_DIM`.
4. `no →` chip anchored bottom-right, above its physical button (hardware is the
   legend — existing principle).

Escalation ("hot", ≥10s waiting): the field warms toward `FIELD_LANTERN_HOT` and its
luminance breath quickens (4s → 1.2s, ±6%). **No numeric wait counter** — urgency is
light and motion, not a stopwatch. (The seconds counter dies with the HUD.) After 2
minutes unanswered the field decays toward ember with a top-edge pulse (§2.1.4).

Outcomes:
- **Approve (crown):** card pops (scale-out, 150ms), green ripple, then the **snuff** —
  light contracts back into the face and goes out over ~250ms, face crossfading ink →
  glow. Happy-squint, small `yes!` bubble in Night mode until the desktop clears the
  prompt (existing clear semantics).
- **Deny (right):** solemn nod (existing), field **fades** evenly to black over ~350ms,
  neutral `okay` bubble. No guilt animation.
- **Link lost mid-prompt:** the card's bottom line becomes `link lost!` in `HOT`
  (existing honesty rule — a boop can't be delivered, say so). The field stays lantern:
  the human is still needed, just not answerable from here.

Unchanged invariants: arming delay, wake-press guard on both buttons, prompt takes
over menu/glance and reverts unconfirmed menu previews, `{"cmd":"permission",…}` wire
format.

## 8. Completion → the gift loop

Trigger: heartbeat `pet=celebrate` with a `Done`-prefixed `msg` (existing gate).

1. **Celebration burst** (~2.5s): arc eyes + confetti + green→warm halo ripple.
2. **Gift-waiting** (device-local state): a gold twinkling orb persists near the face;
   the idle face carries a subtly expectant look (slightly raised brows variant).
   Survives pet-state changes back to idle/busy; suppressed (not cleared) while a
   prompt or error is displayed.
3. **Collect:** crown tap (when no prompt/error) pops the orb — sparkle burst, giggle
   squish — and the `Done: …` summary appears in a bubble for 4s, then fades.
4. One gift slot: a newer completion replaces the pending one (its summary replaces
   the old). Glance card shows `gifts: N` if the desktop reports more than the device
   tracks; device-side we keep exactly one.
5. Uncollected gifts survive dim/off and sleep; they do **not** survive reboot (no
   persistence — the desktop remains the source of truth for history).

Nothing is sent upstream on collect in v1 — but note this is now a deliberate choice
rather than an architectural limit: boops already round-trip (§4), so a
`{"cmd":"collect"}` mirroring the gift to the Mac popover is a small, precedented
addition whenever the desktop wants it.

---

## 9. Presence, link, and the dim ladder

### 9.1 Presence: three link states, routed by the bond store

The tension: a never-paired device must fail loudly (nothing works; the user needs
instruction), but a paired device whose laptop went to sleep must stay cute (the
condition is routine and self-heals). The resolver is the **bond store**: the loud
state is gated on "no bond has ever been stored," a condition that exists only before
first adoption (or after an explicit unpair/factory reset) — so a customer sees it
exactly once, and every later interruption presents as rest.

All three signals are local to the device; no wire change:

| Condition | Signal | Presentation |
|---|---|---|
| **Never adopted** (no bond in NVS) | `bleBonded()` false (new accessor) | **Pair-me** — loud, in-universe |
| **Adopted, link down** (laptop asleep/away, app quit) | bond exists, `dataConnected()` false | **Nap with dream glyph** — quiet, honest |
| **Adopted, link up, data stale** (app hung/misbehaving) | `bleConnected()` true, `dataConnected()` false | Same nap; glance card reads `connected, no data` (the debugging tell) |

**Pair-me.** Not an error screen — the buddy is waiting to be adopted. Face awake and
curious, glancing around; a speech bubble cycles (~4s) between `pair me!` with a
Bluetooth glyph and the advertised name (`I'm "Boop"`). Halo: soft blue breath —
the one state that wears Bluetooth blue, so the color itself says "radio". **Pair-me
stays in Night mood** despite being actionable — it can persist for hours on an
unadopted device, and a permanent lantern field would burn power and panel for a
message nobody is currently reading. It blooms to Lantern for ~3s on any button press
or touch (someone is engaging → show the instruction loudly), then settles back. The
dim/off ladder applies normally, but any wake input returns to pair-me, not idle. Entered
from the hatch ritual (§13) and after `unpair`/factory reset. The existing passkey
takeover (priority 2) handles the pairing moment itself; on bond success → sparkle +
happy squint → normal presence rules take over.

**Nap (link down, adopted).** 10s grace (radio hiccups are invisible), then drowsy
over ~3s — heavy lids, a yawn — then sleep with drifting z's. Sleep *is* the
disconnected indicator: nothing can happen without the brain, and a napping buddy is
honest about that. The honest whisper: an occasional **dream bubble drifts up
containing a tiny crossed-out-Bluetooth glyph** — the marker that distinguishes
link-down sleep from commanded sleep (long-press) or a face-down nap, for the user
who looks closely. Poking a link-down sleeper does the sleep-peek (existing) and
surfaces the dream bubble briefly, then it dozes back off — sleep is a mood, not a
wall. The glance card states the fact plainly: `link lost · 12m` (age since last
data).

**Reconnects:** short drop (<5min) → simple wake, eyes open, small blink, back to the
heartbeat's state, no fanfare. Long absence (≥6h) → morning ritual (§13). Bonded
re-encryption is automatic (stored keys) — the passkey screen never reappears for a
healthy bond.

### 9.2 Dim/off ladder (existing, restated)

Idle 5min → fade to dim; 10min → screen off. Ladder restarts from last user input
(existing fix — keep). Any input wakes (wake press never acts — existing guard).
Never dims with a prompt pending. Face-down (§10.2) short-circuits to nap.

---

## 10. Affection inputs

### 10.1 Touch (FT3168, poll) — **[shipped]**, one gap

Already live and hardware-verified:

- **Tap** = a boop (local heart flash + `{"cmd":"boop"}` upstream).
- **Sustained petting**: holding or stroking refreshes the affection window every loop
  and re-sends the upstream boop on the 1.5s rate limit, so the heart persists for the
  whole stroke on *both* pets. The heart face rains drifting mini-hearts past the
  cheeks — deterministic-phase particles (no `rand()`), so HIL screenshots stay
  reproducible. Hearts are sized for 340 PPI (r=9..12 ≈ 3–4mm on glass; the first cut
  at r=4..6 was physically invisible).
- **Touch on a sleeping face**: sleep-peek for as long as you stroke, without waking.
- **Ignored entirely while napping**, so a couch pressing the panel can't boop the pet
  into a wake loop.
- Touch never actuates anything (doctrine #4) — never approves, denies, or opens the
  menu, and never acts while a prompt is pending.

**Remaining gap — gaze tracking.** This spec's "eyes follow the finger" (clamped pupil
offset, spring-smoothed, with a contented half-blink) is *not* built; touch currently
produces affection, not attention. That is the §5 deliverable. Note the open FT3168
investigation first: raw-contact telemetry (`touchEdges`, `touchContactMaxMs` in
`state`) was added to diagnose suspected stationary-finger dropout — if a held finger
stops reporting, gaze tracking will stutter, so settle that before tuning the spring.

### 10.2 IMU (QMI8658C) — **[shipped]** except pick-up

Driver: probes 0x6A/0x6B on the shared touch I2C bus, ±4g @125Hz, polled 20Hz via
`halImuRead()`. Detection lives in `motionTick()` (`main.cpp`). All effects
display-only.

| Gesture | Status | Behavior |
|---|---|---|
| **Face-down** (panel-normal < −0.75g for 2s) | **[shipped]** | Nap: screen dark and stays dark; time accrues into the `napSeconds` stat (the menu's "naps" line is real data). Blocked while a prompt pends. Face-up with 700ms debounce wakes. |
| **Shake** (leaky accumulator over \|magnitude − 1g\|) | **[shipped]** | ~3s dizzy X-eye wobble. Suppressed while a prompt is pending. |
| **Pick-up** | **not built** | *dangle mode*: pupils/eye offsets driven by the accelerometer through a spring (they jiggle with real motion); a mini summary bubble floats up while airborne — `3 tasks · 2 approvals · 1 gift`. Ends after ~1s of stillness. |

**Nap can never trap the pet** — three shipped rails, all of which must survive any
change here: the IMU backs off 500ms on I2C errors rather than hammering a flaky bus;
a sensor silent >5s mid-nap fails the nap *open* and restores the screen; and any
physical button press ends a nap instantly and restarts the 2s face-down debounce so
you get real lit-screen time rather than a 50ms re-nap.

Thresholds were tuned by injection plus one hand test and may want a feel pass
(`FACE_DOWN_G`, shake threshold 2.5, decay 0.8 at the top of the motion section in
`main.cpp`). Tune conservatively: a missed shake costs nothing; a false face-down nap
is genuinely annoying. Use `imu set x y z` / `imu clear` to drive the detectors without
touching the board.

Pick-up detection must be built to coexist with these: it shares the same sample
stream, and a lift is easy to confuse with the start of a shake. Gate dangle mode on
sustained orientation change *without* the shake accumulator tripping.

---

## 11. Busy theater

The busy face already shows the heartbeat `activity` verb. End state: the verb also
selects eye behavior.

| activity | Eyes |
|---|---|
| reading / searching | scan left-right, line-by-line saccades |
| testing / building | squinted concentration, occasional determined blink |
| writing / editing | steady focus, tiny nods |
| (any, task ≥3min) | rare "phew" — one eye-wipe animation, then back to work |
| unknown verb | default half-lids + working dots (existing) |

---

## 12. Micro-idles

Rare randomized moments while idle (and only idle). Global minimum spacing **≥90s**,
uniform-random selection, each ≤2s:

1. big yawn
2. eyes chase a passing orb one full loop
3. happy wiggle (small x-axis spring)
4. one slow, direct look "at" the user, single blink
5. ear-less head tilt (whole-face 4° rotation, springs back)

Rarity is the charm. These never fire during busy/attention/error, never within 10s of
a real interaction (the real interaction *was* the moment).

---

## 13. Rituals

- **Hatching (first-ever boot,** NVS one-shot flag**):** egg on black → rock, rock →
  crack lines → burst → blinking newborn face → settle into **pair-me** (§9.1 — a
  newborn has no bond yet). ~6s total, skippable by any button. This is the unboxing
  moment; it must feel hand-finished.
- **Morning stretch (first link-up after ≥6h offline/asleep):** stretch (face scales
  up 5% with raised brows) + big yawn + settle, ~2s. Time source: heartbeat time-sync
  delta (no RTC — lost on reboot; on reboot-then-connect, show the stretch: fresh boot
  feels like waking up anyway).
- **Adoption (menu species pick):** existing preview/adopt/persist flow unchanged; add
  a small sparkle-squish on adopt confirm.

---

## 14. What is deleted

- The 52px resting HUD block: `connected/disconnected` text, `pet | species` line,
  `sessions: N rN wN` line, bottom `Done:` line (replaced by §8), and the approval
  card's `waiting Ns` counter (replaced by §7 escalation). On `HAL_LANDSCAPE` only —
  the M5 portrait renderer keeps its HUD and remains the regression rig.
- No other behavior is removed. Menu grammar, arming, wake-guard, species persistence,
  OTA/passkey screens, screenshot/HIL plumbing all stay.

---

## 15. Build order and code map

Approved sequence (2026-07-25). Each step ships independently; HIL stays green
throughout (M5 suite untouched, WS suite updated per step).

| # | Deliverable | Spec | Touches |
|---|---|---|---|
| 1 | Kill resting HUD; full-bleed face; glance card on look-tap | §3, §6, §14 | `main.cpp` render branch, new `glance.h`; `menu.h` hold-to-open |
| 2 | **Mood/field system** (Night/Ember/Lantern, bloom/snuff/fade transitions, ink-face inversion) + halo renderer | §2.1, §3.1 | new `mood.h` owning field color + transition clock; `face.h` gains an ink/glow weight factor; dither util |
| 3 | Session orbs | §3.2 | new `orbs.h`, reads `tama` counts |
| 4 | Approval card v2 (lantern bloom, face persists, escalation, decay) | §7 | `main.cpp` prompt branch → new `bubble.h`, drives `mood.h` |
| 5 | **Extend:** boop squish spring + touch-tracked gaze (petting itself is shipped) | §10.1, §5 | `face.h` springs, FT3168 poll path; settle the touch-dropout investigation first |
| 6 | **Extend:** pick-up / dangle mode only (driver, shake, face-down nap all shipped) | §10.2 | `motionTick()` in `main.cpp`, reusing `halImuRead()` |
| 7 | Gift/collect loop | §8 | device-local state in `main.cpp`/`face.h` |
| 8 | Hatch + morning stretch rituals | §13 | NVS flag in `stats.h`, sequences in `face.h` |
| 9 | Micro-idles + busy theater | §11, §12 | `face.h` |
| 10 | Presence states: pair-me screen + dream-glyph nap + glance link line | §9.1 | new `bleBonded()` in `ble_bridge`, `face.h`, `glance.h` — rides naturally with steps 1–2 |

**No heartbeat/wire changes are required for the remaining steps** — everything reads
existing `RenderState` fields (`pet` including `heart`, `activity`, `msg`, session
counts, prompt metadata). This is *not* because the wire is frozen: the one-creature
pass already added `{"cmd":"boop"}` upstream and `pet:"heart"` downstream, so
extending the contract is precedented and cheap when a feature genuinely needs it.
Deferred by choice, not by rule: per-session summaries for glance pages (§6),
collect-acknowledgment upstream (§8), and boop counting (naps are already a stat;
boops are not).

### Testability requirements (per step)

- **Baseline to keep green: USB HIL 34/34** on hardware (plus BLE e2e proven, HTTP e2e
  40/40, app unit tests 144). Do not let this spec's work regress it.
- `state` already reports `boop`, `napping`, `dizzy`, `ladder`, `touchOk`, `imuOk`,
  `touchDown`, `touchEdges`, `touchContactMaxMs`, `draws`, `tick`. It grows as
  features land: `glance`, `gift`, `orbs`, `bonded`, `mood` (night/ember/lantern +
  transition progress).
- Synthetic injects already exist and should be reused rather than reinvented:
  `press a|b|m`, `touch down|up` (`synthTouch`), `imu set x y z` / `imu clear`,
  `deepsleep [ms]`, `mockprompt [fresh]`. Pick-up detection (§10.2) is testable
  through `imu set` with no new inject.
- Screenshot-based checks remain the visual oracle (456×280 native dumps). The mood
  system is unusually testable this way: assert the field's corner pixel is black in
  Night, `#FFDBAD` at lantern peak, and mid-transition during a bloom — a cheap,
  precise regression test for the whole alert channel.
- Soak (`tools/soak.py`) gains glance-card and gift cycles; heap floor re-checked
  after the halo/orb allocations (all buffers static or PSRAM).

---

## 16. Open questions (tracked, not blocking)

- **Sound, later:** if a v1.x hardware rev adds a piezo/I2S speaker on a header GPIO,
  the Blob chirp grammar (PRODUCT.md §10.3) applies unchanged. Nothing in this spec
  reserves screen real estate or timing for audio.
- Multi-gift stacking and per-session orb identity — wait for real usage; both have
  wire-contract implications.
- **FT3168 stationary-finger dropout** (open investigation, telemetry already latched
  in `state`) — blocks touch-tracked gaze in step 5.
- **Buttons are not soldered yet.** IO1/IO2/IO5 are live in the HAL, so this spec's
  work can proceed on BOOT + synthetic presses, but button *feel* — especially the
  crown hold ladder and the 600ms arming window — needs the physical switches before
  it can be judged.
- Affection is one-directional (device → desktop). The desktop can't boop the device;
  the mirror-back only makes it look mutual. Worth revisiting if the Mac popover ever
  wants to initiate.
- Quiet-hours schedule without an RTC (time survives only while linked) — probably
  desktop-driven: the Mac app sends sleep/wake hints. Not v1.
