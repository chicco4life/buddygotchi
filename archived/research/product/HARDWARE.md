# Buddygotchi Hardware Build Plan

Status: draft v2 — rewritten around the simplified **v0 rigid design** (boop button, no silicone squish mechanism); the squish crown moves to §12 (future evolution)
Last updated: 2026-07-04
Companion to: `PRODUCT.md` (strategy, form factor §9, interactions §10), `MARKETING.md` (positioning; assumes retail **$149**)

This document walks through exactly how the physical product gets built: every component, why it was chosen, how it all assembles, and how the process changes across three phases — **Development** (prototypes on your desk), **Initial Batch** (the Founding Litter of 100, hand-assembled in China), and **Scaled Production** (1,000+/year on our partner's injection molding machines). It is written for a reader with zero hardware or manufacturing experience; terms are explained the first time they appear.

Where this conflicts with `PRODUCT.md` §4 (M5StickC Plus 2) or §9.5 (silicone squish cap + internal chassis), this document wins: the board decision changed after re-weighting form factor above firmware risk, and the input mechanism was simplified for v0 (rationale in §2).

---

## 1. What we are building, in one paragraph

A rigid, frosted, translucent blob (~80 mm wide) that sits on a desk, plugged into USB-C power. Its face is a dark "visor" window behind which an AMOLED screen renders eyes and expressions. On its crown sits one satisfying domed button — a real mechanical keyboard switch under a custom cap — that you **boop to approve**. A recessed button on the back denies. Inside: one off-the-shelf Waveshare board (screen + processor + Bluetooth + motion sensor, all pre-built), two RGB LEDs that make the shell glow, a small buzzer for chirps, and a steel disc in the base that makes it wobble upright like a roly-poly toy when poked. The Mac app is the brain; the device is a terminal. Nothing in this plan involves designing a circuit board — we buy the complicated electronics finished and add only parts that connect with two wires each.

### The architecture rule that shapes everything

**Everything mounts to one rigid part.** The device has exactly two structural pieces: the translucent shell (the pretty outside) and the base-chassis (the single rigid skeleton that carries the board, both switches, LEDs, buzzer, steel weight, and USB port). The whole assembly wobbles as one lump, so nothing inside ever moves relative to anything else — which is what makes the wobble mechanically harmless (§10).

---

## 2. Why v0 is rigid: what we cut and why it's safe to cut

The original form-factor plan (PRODUCT.md §9.5) specified a soft silicone crown driving a plunger onto a switch — "a marshmallow that clicks." That squish mechanism was the most complexity-dense subsystem in the product:

- a **made-to-order silicone part** (its own supplier, a ~$300 mold, first-article iterations),
- a **plunger riding in a guide bore** — the tightest tolerance stack in the device, and the part most likely to feel wrong across 100 hand-assembled units,
- **capture geometry** in two other parts (silicone bonds to almost nothing, so it must be mechanically trapped),
- a separate **internal chassis** whose main job was guiding that plunger,
- and several weeks of feel-tuning in the development phase.

v0 deletes all of it. The affirmative gesture becomes a **boop** — a poke on a satisfying hard button — which aligns with the Boop branding better than "pet/squish" did: a boop is a poke, and poking a rigid wobbling creature that rocks and giggles is exactly the product. What survives untouched is everything the audience demonstrably pays for: the steel heft, the frost finish, the glow, the wobble, the AMOLED face, and the box.

The trade, stated honestly:

- **Gained:** ~$6–8 off unit cost; assembly drops ~15 → ~8–10 min; one supplier and the riskiest tolerance stack eliminated; development shortens by roughly a month; part count ~20 → ~14 line items; and the button *feel* is bought from a mature market (mechanical keyboard switches) instead of engineered by us on the first try.
- **Lost:** the marshmallow squish. The shell is rigid (it always was — only the crown was soft); the cuddle factor now rides on the mochi frost, the dome silhouette, and the wobble.
- **Deferred, not dead:** the squish crown returns as a v2 premium evolution when volume justifies it (§12).
- **Copy implications** (flagged for the landing page, not changed here): "approve with a pet" → "approve with a boop"; the S6 "silicone crown that clicks like a marshmallow" line → the truthful and arguably stronger "a real mechanical switch under its hat." Tracked in §13.

---

## 3. The electronics platform: Waveshare ESP32-S3-Touch-AMOLED-1.64

**What it is:** a finished, tested mini-computer board with the screen already attached. One purchase gets us:

| Onboard | Detail | What we use it for |
|---|---|---|
| Screen | 1.64" AMOLED, 280×456 px, CO5300 driver, ~35.5×21.8 mm active area mounted landscape | The visor face. AMOLED = each pixel emits its own light; black pixels are *off*, so behind a smoked lens the panel edges vanish and only the eyes/visor show |
| Processor | ESP32-S3R8 dual-core, 240 MHz | Runs our firmware (ported from the M5StickC version) |
| Radio | 2.4 GHz Wi-Fi + **Bluetooth 5 LE** | The BLE link to the Mac app (heartbeat, approvals, OTA updates) |
| Memory | 16 MB flash + 8 MB PSRAM | Dual OTA partitions + animation assets, per PRODUCT.md §2.3 |
| Motion sensor | QMI8658 6-axis IMU (accelerometer + gyroscope) | Side-boop / shake / pick-up detection — display-only reactions, never approvals (§10.1 of PRODUCT.md) |
| Touch layer | FT3168 capacitive touch | **Unused.** It comes laminated into the screen; we simply never initialize it |
| Ports | USB-C (power + flashing), TF card slot, battery header | USB-C only. Battery header stays empty forever (PRODUCT.md §2.1) |
| Expansion | Exposed USB / UART / I2C / GPIO pads | Where our switches, LEDs, and buzzer connect |

**Price:** ~$23 single-unit retail; target **$18–20** at 115 units direct from Waveshare's B2B channel (or Taobao domestic pricing via our China partner).

**What the board does NOT have — the complete list of what we add:**

1. **Two user buttons** in useful positions (it has RST/BOOT buttons on the PCB, wrong places) → the crown boop switch and the rear deny switch (§4.2).
2. **A buzzer/speaker** → a small buzzer module (§4.4).
3. **Shell glow** → two WS2812B RGB LEDs (§4.3).
4. **An enclosure** → the blob (§4.5–4.7).

**Verify-on-receipt list** (facts to confirm against the schematic and wiki before freezing the design — see §13): which exact GPIO numbers are free on the expansion pads; whether an RTC chip is present (if not, no problem: the device is always USB-powered and the Mac app can sync time over BLE at connect); the availability of a STEP file (a 3D CAD model of the board — Waveshare publishes these for most boards, and it makes designing the base-chassis far easier than measuring by hand).

---

## 4. Complete bill of materials

A **BOM (bill of materials)** is the master parts list: every physical thing in one unit. Prices are estimates: first number ≈ small-quantity/prototype, second ≈ at 100 units, third ≈ at 1,000+.

### 4.1 Master BOM summary

| # | Part | Qty | Dev / 100 / 1k+ each | Section |
|---|---|---|---|---|
| 1 | Waveshare ESP32-S3-Touch-AMOLED-1.64 | 1 | $23 / $19 / $15 (OEM) | §3 |
| 2 | MX-style silent-tactile mechanical switch (crown/boop) | 1 | $0.60 / $0.45 / $0.30 | §4.2 |
| 3 | Custom domed keycap for #2 | 1 | $1.50 / $0.80 / $0.30 (molded) | §4.2 |
| 4 | Tactile switch, firm (rear/deny) + printed cap | 1 | $0.30 / $0.20 / $0.10 | §4.2 |
| 5 | WS2812B RGB LED on mini breakout | 2 | $0.40 / $0.25 / $0.10 | §4.3 |
| 6 | Level-shifter breakout (74AHCT125-class) | 1 | $0.50 / $0.30 / $0.05 | §4.3 |
| 7 | Passive buzzer module (with driver transistor) | 1 | $0.60 / $0.40 / $0.15 | §4.4 |
| 8 | Translucent outer shell | 1 | $18 / $12 / <$2 (molded) | §4.5 |
| 9 | Base-chassis (single rigid skeleton) | 1 | $10 / $6 / <$1.50 (molded) | §4.5 |
| 10 | Steel disc 40×6 mm, zinc-plated (~59 g) | 1 | $2 / $1 / $0.50 | §4.6 |
| 11 | Silicone foot ring, die-cut, Shore ~60A | 1 | $1.50 / $0.60 / $0.20 | §4.6 |
| 12 | Smoked acrylic lens, laser-cut, 1.5 mm | 1 | $2 / $0.80 / $0.30 (molded PC) | §4.7 |
| 13 | Opaque light baffle (printed or die-cut) | 1 | $0.50 / $0.30 / $0.10 | §4.3 |
| 14 | Internal right-angle USB-C extension (panel-mount female) | 1 | $2.50 / $1.80 / $0.90 | §4.8 |
| 15 | Wiring: pre-crimped JST-PH pigtails + 28 AWG silicone wire | set | $1.50 / $1 / $0.40 | §4.9 |
| 16 | Heat-set brass inserts M2.5 + screws M2.5×6 | 4+4 | $0.70 / $0.50 / $0.25 | §4.9 |
| 17 | Adhesives (epoxy, B-7000, VHB tape) amortized | — | $0.80 / $0.40 / $0.20 | §4.9 |
| 18 | Braided cream right-angle USB-C cable, 1.5 m | 1 | $4 / $2.50 / $1.50 | §4.8 |
| 19 | Adoption box + insert + printed card + sticker | 1 | $8 / $5 / $2.50 | §4.10 |
| | **Parts subtotal** | | **~$79 / ~$53 / ~$26** | |

(Dev-column prices are inflated by small-quantity shipping and one-off print runs; that's normal.)

### 4.2 The boop button — a real mechanical keyboard switch

This is where the v0 cost-cut becomes a *feature*.

The crown button is an **MX-style mechanical keyboard switch** — the exact component the mechanical-keyboard hobby is built on. Why it's the perfect part here:

- **The feel is already world-class.** Decades of refinement, dozens of force curves, an entire vocabulary (tactile/linear/clicky) — we *select* a great feel instead of engineering one.
- **Absurdly durable:** rated 50–80 million presses (the Omron tact switch we'd otherwise use is rated ~1M; either outlives the product, but 50M is a marketing-grade number).
- **Standard mounting:** a 14×14 mm square cutout in a 1.5 mm plate — trivially printed/molded into the base-chassis crown. The switch clips in; no glue, no screws.
- **Standard cap interface:** the cross-shaped "MX stem" takes any keycap, so our crown cap is just a custom keycap — and later, swappable caps become the accessory line ("hats"), riding an ecosystem our customers already own (§12).
- **The story tells itself** to this audience: *"the approve button is a real mechanical switch — silent tactile, of course."*

**Which switch:** a **silent tactile** — a soft bump you feel, with rubber-dampened travel so there's no loud clack on the desk (the device is a calm companion; a blue clicky switch would be off-brand). Candidates to sample: Gazzew Boba U4 (the community's reference silent tactile), Gateron Silent Brown, Kailh Silent Box Brown. Buy a switch sampler pack (~$15 from any keyboard shop) and pick by feel in the printed test block — same selection-by-finger process as before, now from a much better menu. Electrically it's identical to any switch: two pins → one to a free GPIO, one to GND, internal pull-up (`INPUT_PULLUP`), pressed = LOW, ~20–30 ms firmware debounce. (A "pull-up" holds the pin HIGH through a resistor inside the chip until the switch connects it to ground; "debounce" means ignoring the few milliseconds of electrical chatter as the contacts settle.)

**The cap:** a low dome (~18–20 mm across, gentle concave dish for the fingertip) with a standard cross stem underneath, sitting in a recessed dish in the shell crown so it reads as part of the body, not a button sticking out. Dev/batch: SLA-printed in tough resin, bead-blasted to match the shell (verify stem fit early — the cross socket has fine features; one test print settles it). Scale: molded, or sourced from a keycap manufacturer (blank DSA/XDA-profile caps cost cents and custom-molding a dome is a routine job for them). MX travel is ~4 mm with a damped landing — pressing straight down on a roly-poly is stable (the force passes through the base's center), so booping the crown clicks; booping the *side* wobbles. Two different gestures, mechanically disambiguated for free.

**The deny button:** stays a humble firm tact switch (Omron B3F-class, ~2.5 N so it can't false-trigger) behind a small printed cap, recessed into the rear of the base-chassis — reaching around back is the "deliberate beat of intention" PRODUCT.md §10.1 wants. Denial doesn't need to feel luxurious; it needs to feel *definite*.

### 4.3 Shell glow: 2× WS2812B LEDs + baffle

A **WS2812B** is an RGB LED with a tiny controller inside: power, ground, and one data wire on which the chip sends color commands; multiple LEDs chain on the same wire. Buy them pre-soldered on ~10 mm round breakout boards (search "WS2812B pixel board") so there's no surface-mount soldering. One aims up into the dome, one aims down through the base ring for the desk halo (PRODUCT.md §9.3).

**One real gotcha:** WS2812Bs run on 5 V (available from the board's USB-C input rail) but our GPIO signals are 3.3 V — marginally below the WS2812B's specified data threshold. It often works anyway; "often" is not production. The clean $0.30 fix is a single **level shifter** (a chip that converts 3.3 V signals to 5 V — a 74AHCT125-class breakout at dev, one tiny chip on the harness at scale). Test without it during development; ship with it.

The **baffle** is a matte-black opaque sleeve (printed, or die-cut adhesive felt/card at scale) around the board so the LEDs light the shell, not the electronics silhouette. Shadowed internals ruin the glow; this is a $0.30 part that matters.

### 4.4 Sound: passive buzzer module

The 1.64 board has no buzzer (the StickC did), so we add one. A **passive buzzer** is a tiny speaker-like disc that plays whatever frequency the chip drives it with — exactly right for chiptune chirps (an *active* buzzer plays one fixed annoying beep; wrong part). GPIO pins can't supply enough current to drive one loudly, so buy the **3-pin "passive buzzer module"** with the driver transistor already on it: power, ground, signal. At scale, the disc + transistor move onto the harness PCB (§9.2). Firmware drives it with PWM (the ESP32's LEDC peripheral) and enforces the hard volume cap from PRODUCT.md §10.3.

### 4.5 The two structural parts

- **Outer shell** — the blob body. One piece of rigid translucent material, drops over everything, retained by an elastic lip that snaps onto a groove in the base-chassis (no visible fasteners anywhere; comes off with firm thumb pressure for service). Openings: the visor aperture with its 1 mm lens recess, and the crown dish with the keycap hole. **Development/Batch:** SLA-printed translucent resin. *SLA (stereolithography)* is 3D printing where a laser cures liquid resin layer by layer — the only common printing process that produces genuinely translucent, smooth parts. Finish: interior lightly polished (light transmission), exterior fine bead-blasted for the matte "mochi" frost — order the finishing from the print bureau, it's a standard service (~$2–4/part). One durability note a beginner won't expect: **clear resins yellow slightly with UV exposure over months.** Our warm off-white "Mochi" tint conveniently makes this invisible — specify the warm tint *in the resin*, not as a coating, and yellowing disappears as a concern. **Scaled:** injection-molded frosted polycarbonate (§9.1).
- **Base-chassis** — the single rigid skeleton, and the part that replaced two parts (the old separate chassis + base cup). It carries, as designed-in features: four bosses with heat-set inserts for the board; the 14 mm MX switch plate at the crown position; the rear deny-switch pocket and cap bore; LED cradles and baffle seat; buzzer mount; the steel-disc pocket in the floor; the USB-C bulkhead hole; the shell snap groove; and the spherical bottom cap that the foot ring sticks to. It doesn't need to be pretty or translucent — it needs to be stiff and dimensionally accurate. **Dev/Batch:** MJF nylon (PA12). *MJF (Multi Jet Fusion)* prints tough, precise nylon parts cheaply — stronger and more temperature-stable than SLA resin, ideal for structural parts; Chinese bureaus (JLC3DP, WeNext, any Taobao print shop) print it for a few dollars. **Scaled:** injection-molded ABS.

**Tolerance note for the CAD work:** printed parts vary by ±0.2 mm or so. The MX switch is forgiving (it clips into its plate and the cap has its own travel), which is precisely why this design is beginner-friendly — the one high-precision mechanism in the old plan (the guided plunger) no longer exists. The remaining fits that deserve care: the keycap-to-shell dish clearance (target ~0.5 mm all around so it never rubs) and the lens recess.

### 4.6 The wobble: steel disc + foot ring

- **Steel disc:** 40 mm diameter × 6 mm mild steel ≈ 59 g, **zinc-plated** (bare steel rusts; plating is pennies). A standard laser-cut item from any Chinese metal shop, ~$0.50–1.50. Epoxied into its pocket in the base-chassis floor (the one glue joint we keep — steel-to-plastic epoxy is strong and this joint is never stressed). It forces the center of mass below the base sphere's center of curvature → the blob self-rights. Total device weight target 150–180 g; if wobble tuning (§7.2) wants more mass, spec an 8 mm disc.
- **Foot ring:** the damper. Die-cut from 2–3 mm silicone sheet, Shore ~60A (Shore A is the rubber-hardness scale; 60A ≈ a pencil eraser), adhesive-backed (3M 468MP transfer tape) onto the spherical bottom. Die-cutting (a steel cookie-cutter press) is the cheapest way to make consistent rubber rings; any gasket shop does it. Ring width is the damping tuning variable: wider ring = fewer, shorter rocks. Target per PRODUCT.md §9.4: 2–3 damped rocks, then stillness — "settles like a contented animal."

### 4.7 The lens

Laser-cut **1.5 mm smoked (gray-tinted) cast acrylic**, sitting flush in a 1 mm recess over the visor aperture, fixed with thin VHB tape or a bead of B-7000 around the perimeter (both are removable-ish for rework; B-7000 is the phone-repair glue — beginner-friendly, forgiving). Because the panel is AMOLED, **no printed bezel mask is needed** — off pixels are invisible through the smoke, so the visor shape is drawn in firmware and the lens is just a clean dark window. Development determines the smoke level: order 30% and 40% transmission coupons and pick against the real panel (§7.2). Scaled: molded polycarbonate lens, tinted in-material.

### 4.8 Power and cable path

- **Internal:** a panel-mount **USB-C extension** (female socket on a short pigtail, male end into the board's port). The socket bolts into the base-chassis at the back, high, feeding the strain-relief channel. Why not use the board's own port through a hole? Because then the shell geometry is hostage to the board's port position, every cable insertion stresses the board's solder joints, and flashing during assembly needs the case open. The $1.80 extension decouples all three. Buy a right-angle-exit variant so the internal loop is gentle.
- **External:** the **1.5 m cream braided right-angle USB-C cable** in the box. Custom braided cables in a specified color are a standard Alibaba item (MOQ ~100–500, $1.50–3). PRODUCT.md §9.4 is right that this is a no-skimp item: a stiff straight cable levers the wobble dead and reads cheap. Right-angle plug + braid drape = the cord disappears.

### 4.9 Wiring, fasteners, adhesives

- **Harness:** all internal connections use **pre-crimped JST-PH 2.0 mm pigtails** (buy them with the wires already crimped in — crimping your own is a skill and a tool purchase you don't need). **Idiot-proofing rule: every subassembly gets a different pin count** so nothing can be plugged into the wrong socket: buzzer = 2-pin, LEDs = 3-pin, switches = 4-pin (both switches sharing a ground), USB extension is its own connector. Wire: 28 AWG silicone-jacketed stranded (flexible, fatigue-resistant, easy to solder). The MX switch's two pins take soldered wires directly (or, at scale, solder to the harness PCB — and see §12 for the hot-swap socket option).
- **Fasteners:** one size everywhere — **M2.5×6 pan-head screws into brass heat-set inserts** (small brass sleeves you melt into printed plastic with a soldering iron; they give printed parts real machine threads that survive repeated assembly). Four inserts, four screws, all for the board. One screw size = one driver on the bench = no mistakes.
- **Adhesives, complete list:** 2-part epoxy (steel disc only), B-7000 (lens, backup for baffle), 3M 468MP transfer tape (foot ring), hot glue (wire strain relief — a dab anchoring each wire near its solder joint so the joint itself never flexes; this is what "strain relief" means and it is the single best habit for reliability, §10.3). Everything else clips, snaps, or screws.

### 4.10 Packaging

The adoption box: rigid two-piece gift box (matte, cream), die-cut insert (EVA foam or molded paper pulp — pulp reads more premium and is what the unboxing photos want), the numbered adoption card, cable coiled beneath, regulatory sticker on the box bottom (FCC/CE text, model, serial). Chinese packaging printers do fully custom rigid boxes at 100 pcs for $3–5; at 1,000+ it's $1.50–2.50. Design the insert so the blob sits face-up and the lid reveal is the face — the unboxing IS the marketing asset (MARKETING.md §4.7).

---

## 5. How it all goes together (the mechanical story)

```
        ┌── domed keycap (in shell's crown dish)
        │     └── MX silent-tactile switch, clipped into
        │         the 14mm plate atop the base-chassis
  ┌─────┴─────┐
  │  SHELL    │  rigid translucent frost, drops over
  │           │  everything, lip-snaps onto base-chassis
  │  ┌─────┐  │
  │  │BOARD│──┼── screen faces visor aperture + smoked lens
  │  │ on 4│  │
  │  │bosses│─┼── LED ↑ into dome   LED ↓ into base halo
  │  └─────┘  │   (black baffle around board; buzzer nearby)
  │           │
  │ BASE-     │── rear: deny tact switch + printed cap,
  │ CHASSIS   │   recessed
  │ (one part)│── USB-C bulkhead → internal extension → board
  │           │── steel disc epoxied in floor pocket
  └───────────┘
     ~~~~~~~ silicone foot ring (the damped wobble contact)
```

Key interfaces, and why each is shaped the way it is:

1. **Board → base-chassis:** 4× M2.5 screws into inserts. Rigid, serviceable, no glue on the most expensive part.
2. **Shell → base-chassis:** elastic lip snap onto a groove. The *only* structural joint in the device, reversible with thumb pressure. (The old design had two joints — chassis-to-base and shell-to-base; merging the rigid parts deleted one.)
3. **Switches:** MX clips into its plate; deny tact switch press-fits its pocket with a dab of B-7000. Caps ride on them directly — there is no plunger anywhere in this product.
4. **The wobble load path:** desk → foot ring → base-chassis → steel mass. The electronics ride above, rigidly coupled — the whole unit rocks as one body; no internal part ever accelerates relative to another.
5. **Gesture disambiguation is geometric:** a vertical press on the crown passes through the base's center of curvature (stable — the click happens, no tipping); a lateral poke on the body tips it (the IMU wobble happens, no click). Boop-the-button and boop-the-body are different inputs without any code having to guess.

---

## 6. Assembly sequence (per unit)

Written as the production procedure for the batch phase; development builds follow the same order, slower. Target: **≤10 min/unit** for a practiced assembler.

1. **Base-chassis prep** (2.5 min): heat-set 4 inserts. Clip in MX switch; seat deny switch + cap. Mount LED breakouts into their cradles, stick baffle sleeve, mount buzzer module. Route harness pigtails; hot-glue strain relief at each solder joint.
2. **Board prep** (2 min, batched separately): flash production firmware over USB *before* mechanical assembly (bare boards flash 20-at-a-time at a bench with a hub). Run the serial self-test (screen pattern, IMU read, BLE advertise — the `handleSerialCommand` path per PRODUCT.md §7). Record MAC/serial in the tracking sheet. Reject fails now, while it's a 60-second swap.
3. **Marry board to base-chassis** (1.5 min): 4 screws, connect switch harness (4-pin), LED harness (3-pin), buzzer (2-pin), internal USB-C extension. Different pin counts make miswiring impossible.
4. **Weight & foot** (1 min; epoxy batched a day ahead — it cures overnight): steel disc seated, foot ring applied, USB-C bulkhead bolted.
5. **Test naked** (1.5 min): power on via the bulkhead. **Full functional test:** both buttons (watch state change), LED cycle, chirp, screen face, side-boop (IMU event), pair with the bench Mac and verify heartbeat + approve/deny + OTA check.
6. **Shell** (1 min): drop keycap onto the MX stem, lower shell over everything, snap the lip. Press the crown — verify the click through the cap and dish clearance. Wobble test: side-boop, count 2–3 rocks, settles.
7. **Pack** (1.5 min): wipe with microfiber, serial sticker on base, box with card + cable, seal.

The order matters: every electrical function is verified **before** the shell goes on (step 5), because reopening after step 6 costs 10× the time of catching it at step 5.

---

## 7. Phase 1 — Development (now → ~6–8 weeks, quantities: 3–10)

**Goal:** retire every design unknown with the cheapest possible experiments, ending with a frozen design ("design freeze" = after this, no changes without restarting validation). The silicone-crown plan needed ~2–3 months; v0 cuts the soft-parts iteration entirely.

### 7.1 Shopping list (~$350 total)

| Item | Qty | ~Cost | Why |
|---|---|---|---|
| AMOLED-1.64 boards | 4 | $100 | One stays pristine (reference), one for firmware, one for the mule, one spare — you *will* kill a board learning |
| Comparison boards: AMOLED-1.8, LCD-2 non-touch | 1 ea | $50 | Lens-test insurance if the 1.64 disappoints |
| MX silent-tactile switch sampler (Boba U4, Gateron/Kailh silents, etc.) | ~10 | $15 | Boop-feel selection |
| Omron B3F assortment (deny switch) | ~10 | $5 | |
| WS2812B breakouts, level shifter, buzzer modules | few | $10 | |
| Breadboard + jumper kit + pre-crimped JST kit | 1 | $15 | First circuits without soldering |
| **Soldering iron** (Pinecil or FX-888D), 63/37 solder, flux, wick | 1 | $40–100 | The one real tool purchase |
| Digital calipers | 1 | $20 | Non-negotiable for CAD around physical parts |
| Multimeter (any $15 one) | 1 | $15 | Continuity beeper = debugging |
| Hot glue gun, B-7000, epoxy, VHB/468MP tape | — | $25 | |
| Smoked acrylic sheet 30% + 40%, A5 pieces | 2 | $10 | Lens test |
| SLA/MJF print runs (expect 4–8 iterations) | — | $60–120 | JLC3DP etc.; each full-set iteration ≈ $25–30 |
| Steel discs 40×6 + 40×8 | 3 ea | $10 | Wobble tuning |

CAD software: Fusion 360 (free personal license) — and note that designing the base-chassis is a task our own coding agents can meaningfully help with once the board's STEP file is imported.

### 7.2 The order of experiments (each de-risks the next)

1. **Bench bring-up (week 1):** run Waveshare's demo firmware; confirm screen, IMU, BLE. Breadboard one switch (GPIO→switch→GND, `INPUT_PULLUP`) and confirm the firmware sees presses. Then LEDs, then buzzer. *Prove every electrical function on the bare board before any mechanics exist.*
2. **Firmware port (weeks 1–3, parallel):** port from M5Unified to this board — CO5300 panel driver (start from Waveshare's demo code), LovyanGFX or esp_lcd rendering, button GPIO mapping, WS2812 driver, buzzer PWM, IMU boop/pick-up detection. Re-validate the full device feature list: heartbeat rendering, approval flow, BLE OTA, animations. (PRODUCT.md's 1–3 week port estimate stands.)
3. **The lens test (one afternoon, decides everything visual):** render the visor face on the 1.64 behind 30% and 40% smoked coupons, in daylight and in the dark-amber scene, next to the 1.8 and the LCD-2 doing the same. Pick panel and smoke level by eye. Photograph everything — this is also build-in-public content.
4. **Switch + cap fit (weeks 2–4):** print the MX plate test block, try the sampler, pick the boop switch by feel. Print keycap candidates — verify the cross-stem fit (the fine features are the one printing risk; one test print settles it) and the dish clearance so the cap never rubs the shell.
5. **Wobble tuning (weeks 3–6):** 3–4 base-chassis iterations varying steel mass (6 vs 8 mm disc) and foot-ring width. Verify the geometric gesture split: crown press clicks without tipping; side boop tips without clicking. Simultaneously tune firmware boop thresholds against the real wobble so the wobble never self-triggers a dismissal (PRODUCT.md §10.5).
6. **Looks-like/works-like unit (weeks 5–7):** first full assembly — frosted shell, tinted resin, real cap, full harness. This is the unit that gets filmed for the waitlist page and carried to the compliance consult.
7. **Burn-in strategy check:** leave a unit running the idle face 24/7 for the rest of development; verify the firmware's anti-burn-in measures (mostly-black visor, pixel-drift micro-movement in idle animations, scheduled dimming, sleep hours) show no image retention after weeks. AMOLED retention is this product's one genuinely novel long-term risk — start the clock early.

### 7.3 Exit criteria (all must be true before Phase 2 spends money)

- [ ] Firmware feature-complete on the 1.64; e2e smoke tests pass against the Mac app over BLE
- [ ] Boop switch model chosen; click feels great through the cap; deny force confirmed
- [ ] Lens smoke level chosen; visor invisible-edge effect confirmed in the dark
- [ ] Wobble tuned; crown-press vs side-boop disambiguation reliable; wobble never self-triggers
- [ ] One looks-like/works-like unit survives 2 weeks of desk daily use + the 24/7 burn-in unit shows no retention
- [ ] Compliance consult done (PRODUCT.md §6): test plan and cost confirmed for this board
- [ ] CAD frozen; all print files, the harness drawing, and the BOM with confirmed part numbers in the repo

---

## 8. Phase 2 — Initial batch (the Founding Litter: 100 sellable + 15 spares)

**Goal:** 100 consistent, certified, sellable units, hand-assembled by our partner in China, at ~$53 parts + labor — while deliberately *not* spending on tooling that scale would obsolete. Timeline: ~2 months from design freeze.

### 8.1 Sourcing rules

- **Everything in one order, one batch, one hardware revision.** All 115 boards from Waveshare at once (B2B channel — ask for: bulk price, the batch/revision guarantee, their FCC/CE test reports for this model, and the STEP file). Dev-board vendors revise silently; a mid-run revision that moves a connector by 2 mm breaks the base-chassis. One batch deletes the risk. Same rule for switches: one reel/bag, one production lot.
- **Supplier map** (all sourceable by our China partner, mostly Taobao/1688): boards — Waveshare direct; prints — JLC3DP/WeNext (SLA shell + caps, MJF base-chassis, finishing included); MX switches — any keyboard-parts vendor (this is a massive commodity supply chain — one of the quiet benefits of the switch choice); tact switches/LEDs/wiring — LCSC + a harness vendor (harness shops deliver the full 4/3/2-wire set assembled to drawing for ~$1/set); steel discs, foot rings, lenses — local laser/die-cut shops; box — packaging printer; cable — Alibaba custom (order 300: batch two will use them, unit cost drops).
- **Incoming inspection:** every board gets flashed + self-tested on arrival (§6 step 2), *within the return window*. Every printed shell gets a 30-second visual against a golden sample. Reject early; at 100 units, *we* are the quality system.

### 8.2 Production, QC, and traceability

Assembly happens at our partner's shop following §6 exactly, written as a one-page illustrated checklist (photograph each step during the first 5 builds — those photos *are* the work instructions). Practical cadence: batch steps across units (all epoxy one day, all base-chassis prep the next) rather than one-unit-at-a-time — 2 people ≈ 115 units in roughly a week of afternoons at the ~10 min/unit target.

Traceability: a spreadsheet row per serial — board MAC, firmware version, self-test result, final-test result, assembler, date, box number. This sheet is the seed of support/RMA (PRODUCT.md §7.6) and, more importantly, the data that tells us in six months whether a failure is a one-off or a pattern.

### 8.3 Compliance and import (the unavoidable homework)

- Per PRODUCT.md §6: the paid compliance consult, then FCC Part 15B unintentional-radiator testing (SDoC route, ~$1–3k) on the finished blob; verify what the board's own radio certification covers (this is a chip-down board — assume finished-product testing is ours). Label text on the base sticker and box. EU/CE: decide now whether batch one ships to the EU; deferring CE is a legitimate scope cut.
- **Import duties:** China-origin consumer electronics into the US have had volatile tariff treatment recently. Before the batch ships, get a customs broker (a few hundred dollars) to classify the product (HTS code) and quote landed duty; **budget 10–30% of the goods value** until quoted, and prefer DDP-style handling on the freight. At 115 units this is one air-freight carton run (~$300–500, a week door-to-door); fulfillment from home in the US.

### 8.4 Unit economics at $149 (batch one)

| | |
|---|---|
| Parts (§4.1) | ~$53 |
| Assembly labor (China, ~10 min + inspection) | ~$4 |
| Freight + duties (est., amortized) | ~$6–11 |
| **Landed cost** | **~$63–68** |
| Payment processing (~3%) | ~$4.50 |
| US outbound shipping (if absorbed) | ~$9 |
| **Contribution per unit** | **~$68–72 (≈ 55% gross margin)** |
| Batch contribution (×100) | ~$6.8–7.2k |
| One-time costs (compliance, dev, spares — no crown mold anymore) | ~$5–7k |
| **Batch P&L** | **≈ break-even to slightly positive, by design** |

Batch one buys: demand proof at $149, the waitlist, ops experience, and every asset Phase 3 needs. (MARKETING.md §3.7's accounting logic stands — v0 just tilts it from "break-even" toward "slightly ahead.")

### 8.5 Exit criteria

- [ ] Sell-through speed + waitlist size say "make more" (MARKETING.md decision framework)
- [ ] Field failure data: DOA rate, 90-day failure modes, support minutes/unit
- [ ] Return rate and top complaint known (watch specifically for "wanted it squishy" — that's the §12 signal)
- [ ] Waveshare OEM/volume quote and M5Stack ODM quote in hand (start both conversations *during* batch one — lead times are 3–6 months)

---

## 9. Phase 3 — Scaled production (1,000–10,000/year)

**Goal:** same product, same feel, ~$26 landed, built on a small production line at our partner's facility — using his injection molding machines, which remove the single biggest capital barrier indie hardware faces.

### 9.1 Injection molding, explained from zero

3D printing builds parts in hours for dollars each; injection molding builds them in *seconds for cents* each — after you pay for the **mold** (also called the *tool*): a precision-machined steel/aluminum block containing a cavity shaped like your part. The machine clamps the mold shut, injects molten plastic, cools it ~20–40 seconds, ejects a part, repeats — thousands of times. The economics: tooling is $2–15k per part *shape* (one-time), parts are then <$0.50–2 each. This is why the blob was designed from day one (PRODUCT.md §9.6) as moldable geometry: one continuous convex surface, a single **parting line** (the seam where mold halves meet — ours hides at the base lip), and **draft** everywhere (slight taper so parts release from the mold — a straight-walled part sticks like a wet glass on a table).

**Our structural advantage:** the partner owns the machines, so we pay for mold steel and machine time at cost, not a molder's margin. And v0 needs only **three tools** (the old plan needed four — the LSR silicone-crown tool is gone):

| Tool | Part | Material | Est. tooling | Part cost |
|---|---|---|---|---|
| 1 | Shell | Frosted translucent **polycarbonate** (tough, glows beautifully, feels dense and premium; PP would be cheaper and feel like a shampoo bottle — this is a spend-here call) | $4–7k | <$2 |
| 2 | Base-chassis | ABS | $3–5k (it's a feature-rich part; still one tool) | <$1.50 |
| 3 | Keycap + deny cap (family mold — multiple small cavities in one tool) | ABS or PC | $1–2k | <$0.30 |

Realistic total: **$8–14k of tooling**, likely less at the partner's cost basis. Lens: molded tinted PC (small tool, ~$1k) or continue laser-cutting — decide on volume. Foot ring: stays die-cut forever; it's already at its cost floor. Keycap alternative: commission a keycap manufacturer instead of tooling ourselves — doming a cap is routine for them and their finish quality is excellent.

### 9.2 Electronics at scale

Two moves, in sequence (per PRODUCT.md §4 Option 2 logic, updated for the new board):

1. **Waveshare OEM (first):** volume pricing on the exact same 1.64 board (~$15–17 at 1k), a written lifecycle/revision commitment, and possibly minor customization (unpopulated battery header, no pin headers). Zero engineering risk — same board, cheaper.
2. **ODM semi-custom (when volume justifies):** the same conversation with Waveshare and/or M5Stack — "this panel + ESP32-S3 module + our connector layout, no touch layer, no battery circuit, delivered flashed and tested." Target $12–15/board at 5k+. Still buy-not-build: they own the schematic, the RF, and the module certification; we specify requirements. Full custom PCB remains off the table (PRODUCT.md §2.6).
3. **The harness becomes a small PCB:** the loose wires, level shifter, buzzer transistor, and LED breakouts consolidate onto one tiny "peripheral board" that the switches and LEDs solder to, with a single connector to the main board. This is a passive, radio-free carrier — a $500 layout job + $0.80/unit that cuts assembly minutes and wiring defects dramatically, and stays within the buy-not-build spirit. This PCB is also where a **Kailh hot-swap socket** for the MX switch can live (§12).

### 9.3 The production line

At 1,000+/year, assembly becomes a stationed line at the partner's shop (2–4 workers, still modest):

- **Jigs** (custom fixtures that hold parts in exactly one position so a step is fast and un-messable — usually just CNC'd or printed blocks): a flashing jig with **pogo pins** (spring-loaded contacts that press onto the board's pads, flash + self-test in one press, no cable fumbling), a base-chassis assembly nest, a lens-setting fixture.
- **Test stations:** 100% functional test (the §6 step-5 script, automated over serial/BLE — a Raspberry Pi bench rig runs it and logs to the traceability DB), plus a **burn-in rack**: every unit runs powered for 4–24 h before packing. Infant mortality (electronics that fail do so disproportionately in their first hours) gets caught in the factory, not on a customer's desk.
- **QC by sampling:** incoming parts inspected per **AQL** (Acceptable Quality Limit — the standard statistical sampling scheme: inspect N of each lot, accept/reject the lot on the count of defects; AQL 2.5 for cosmetics, 1.0 for function is a normal consumer-goods setting). At this stage we also write a one-page **golden-sample agreement** per supplier: a signed-off perfect part that all future lots must match.
- **Serialization:** laser-etched serial on the base (replaces stickers), scanned at each station.

### 9.4 Logistics

Sea freight (30–40 days, ~$0.50–1/unit for something this small) replaces air; goods land at a US **3PL** (third-party logistics warehouse that stores inventory and ships orders for ~$4–7/order all-in) — home fulfillment ends. Returns flow to the 3PL; a spares pool (2–3%) funds advance replacements ("we ship a replacement" stays the policy — reliability-brand-building per PRODUCT.md §7.7).

### 9.5 Unit economics at $149 (scaled)

| | 1,000/yr | 10,000/yr |
|---|---|---|
| Board | $15–17 | $12–14 |
| Molded plastics + caps + lens | $3.50–4.50 | $3–4 |
| Switches, LEDs, harness PCB, steel, ring, cable | $3.50–4.50 | $2.75–3.50 |
| Packaging | $2.50 | $1.75 |
| Labor + test + burn-in | $3 | $2 |
| Freight + duties | $3–5 | $2.50–4 |
| **Landed** | **~$30–36** | **~$24–29** |
| **Gross margin** | **~76%** | **~81%** |
| Contribution after fulfillment + payment | ~$102–107 | ~$108–113 |

At these margins the business constraint is demand generation, not cost — which is the correct problem for marketing to have.

---

## 10. Durability and reliability (ranked by actual risk)

1. **The USB-C cable/connector — the #1 field-failure risk.** A wobbling device with a cable is a fatigue machine if the cable levers on the port. Mitigations designed in: internal panel-mount extension (the board's own port is never touched after assembly), high rear exit with molded strain-relief channel and internal service loop, right-angle external plug. Phase-1 test: 5,000 wobble cycles on the mule with cable attached; inspect.
2. **The boop switch — the most-pressed part, and now the least worrying.** MX switches are rated 50–80M presses; at 50/day that's beyond the product's lifetime by orders of magnitude. Residual mechanical risks: cap-stem wear (negligible — it's the standard interface millions of keyboards use) and cap-to-dish rubbing (solved by the 0.5 mm clearance rule, §4.5). The deny tact switch sees a fraction of the presses and is rated ~1M.
3. **Wire fatigue** — solved by policy, not parts: silicone-jacketed stranded wire, strain-relief dab at every joint, all harnesses restrained to the base-chassis. The §5 rule (rigid inside, one lump) means normal operation flexes nothing.
4. **The IMU and "constant motion":** a non-issue, worth stating for confidence — the QMI8658 is MEMS silicon with no wearing parts; phone-grade sensors survive years of pockets and drops. The wobble is also not constant: 2–3 damped rocks per boop, then stillness. There is no electronic wear mechanism here at all.
5. **AMOLED burn-in — the one novel risk.** An always-on desk device showing a face invites image retention. Firmware owns the fix: mostly-black visor rendering (which the design wants anyway), continuous micro-motion in idle faces (pixel drift, blinks), brightness auto-dim, scheduled sleep. The Phase-1 24/7 unit (§7.2.7) validates before we ship 100.
6. **UV yellowing of resin shells** — hidden by the in-material mochi tint (§4.5); disappears entirely with molded PC at scale.
7. **ESD (static) during assembly:** ESP32 boards are reasonably hardy, but the bench gets $20 of insurance: wrist straps + a grounded mat for anyone handling bare boards. Cheap habit, real DOA reduction.
8. **Thermal:** ~1 W total in a vented shell (port holes + bottom vents double as buzzer grille) — no thermal problem; the battery-free decision (PRODUCT.md §2.1) already deleted the only hot chemistry.

---

## 11. Premium vs cost: the explicit ledger at $149

**Spend (the hands and eyes budget):** shell material + frost finish; the MX silent-tactile switch and the cap's dome/dish geometry (the fingertip moment is the brand); steel heft + tuned damping; the smoked lens flushness; the braided right-angle cable; the pulp-insert adoption box; 100% functional test + burn-in.

**Save (invisible to the customer):** base-chassis material and cosmetics (nobody sees it); no silicone supplier, no plungers, no capture geometry (v0's whole premise); wiring (pre-crimped commodity JST); no battery, no speaker (buzzer chirps are the brand), no touch usage, no third button, no RTC dependency (Mac syncs time); packaging *printing* stays 1–2 colors (design does the premium work, not ink count); sea freight at scale; one screw size; die-cut ring forever.

The through-line: money goes where fingers and eyes go, and nowhere else. That ledger is what justifies $149 without ever saying the word "premium" (MARKETING.md §1.3).

---

## 12. Future evolution (deliberately not in v0)

- **The squish crown (v2).** The original marshmallow mechanism — molded silicone dome, Shore ~30A, driving a guided plunger onto a light tact switch — returns as a premium evolution once volume justifies its tooling and feel-tuning. Design hedge to take now, cheaply: keep the crown region of the base-chassis a defined module boundary in CAD, so a future squish-top variant swaps the crown plate and shell crown without touching anything else. Trigger to revisit: batch-one feedback saying "wanted it squishy," or batch-three differentiation needs.
- **Hot-swap boop switch + cap accessories.** With a Kailh hot-swap socket on the scale-phase harness PCB (§9.2), the boop switch becomes user-replaceable — and custom caps ("hats") become an accessory line riding the existing keycap ecosystem. Switch-feel variants (linear/tactile) could even be a configurator option. Near-zero engineering; pure merchandising.
- **Real speaker** (the ES8311-codec boards in Waveshare's family, or the ODM board) for richer creature sounds — PRODUCT.md §10.3 already scopes this as v2.
- **Color/tint variants** — a resin or masterbatch change, not a tooling change; good merchandising with zero engineering (PRODUCT.md §9.2).

---

## 13. Open items / verify before design freeze

- [ ] AMOLED-1.64: exact free GPIOs on expansion pads (need 2 switches + 1 LED data + 1 buzzer PWM = 4 pins minimum; avoid ESP32-S3 strapping pins 0/3/45/46); confirm from schematic + wiki
- [ ] AMOLED-1.64: RTC present? (Not required — BLE time sync fallback — but changes firmware plan)
- [ ] STEP file availability from Waveshare (else: caliper measurement session)
- [ ] 5 V rail available on the expansion header for LEDs/buzzer, and its current budget
- [ ] Keycap cross-stem printability in SLA tough resin (one test print; fallback: modify an off-the-shelf blank cap)
- [ ] Crown-press vs side-boop stability check on the first mule (the geometric disambiguation in §5.5)
- [ ] Waveshare B2B: bulk price @115, batch/revision guarantee, FCC/CE test reports
- [ ] Compliance consult: chip-down board → confirm full Part 15B scope + quote (PRODUCT.md §6)
- [ ] Customs broker: HTS classification + current duty rate for China-origin finished units
- [ ] Lens smoke % after §7.2.3; final blob dimensions from CAD once the board model is in hand (drives shell/insert/box)
- [ ] Landing page + PRODUCT.md/MARKETING.md copy updates once frozen: boop-not-pet gesture language ("Approve with a boop"), the S6 craft lines (marshmallow → mechanical switch), 1.64" visor specs, ~80 mm body, re-weighed mass ("162 grams of calm"), $149
