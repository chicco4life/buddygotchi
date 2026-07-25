# Boop Product Plan (Hardware + Form Factor)

Status: draft for initial 100-unit production run
Last updated: 2026-07-04

This document captures the plan for turning the Boop hardware companion (currently prototyped on an M5StickC Plus 2) into a sellable product. Sections 1–8 cover sourcing strategy, board options, and manufacturing. Sections 9–10 cover the chosen form factor (the Blob) and its interaction design. Section 11 covers positioning, marketing, and launch. Section 12 covers how the value prop survives the shift to autonomous agents. Section 13 tracks open questions.

---

## 1. Product Context

Boop is a macOS menu bar companion for AI coding agents. The optional hardware device is an ambient desk companion that:

- Displays pet state, species, session counts, and activity over BLE (Nordic UART Service)
- Shows approval prompts and sends approve/deny decisions back via physical buttons
- Receives firmware updates over BLE OTA from the Mac app

**Critical architectural fact:** the Mac app is the brain. The hardware device is a thin display/control terminal. All state, logic, approval routing, and agent integration live on the Mac. This is what makes an off-the-shelf hardware strategy viable — the device only needs a screen, two buttons, BLE, and an LED or two. New product functionality ships as firmware updates (over BLE OTA) and Mac app updates, not new hardware.

---

## 2. Assumptions and Constraints

These are the decisions we are locking in for the first production run. Each one meaningfully simplifies the hardware problem.

### 2.1 USB-C powered only — no battery as a product requirement

The device is a desk companion that sits next to (and talks to) your computer. It will be powered by USB-C at all times.

Why this matters more than it sounds:

- **Deletes an entire failure class.** Battery charging circuits, fuel gauges, protection ICs, and thermal management are where a disproportionate share of first-product field failures happen.
- **Simplifies shipping and compliance.** Lithium batteries trigger UN38.3 testing requirements and dangerous-goods shipping rules (UN3481). USB-only devices ship as ordinary electronics.
- **Simplifies the BOM and the enclosure** (no battery cavity, no thermal isolation).

Note: some off-the-shelf boards we might buy (e.g., M5StickC Plus 2) contain a battery anyway. That's a downside of those options, tracked below — we don't *want* the battery even if it comes for free.

### 2.2 BLE is required, even if initially underused

BLE is the transport for the desktop-to-device heartbeat, device-to-desktop approvals, and firmware OTA. It's also our future-compatibility insurance: any new functionality we ship later (new states, new interactions, new display content) rides on BLE OTA firmware updates plus Mac app updates. Every candidate board must have BLE 5.x. This rules out display-only or WiFi-only boards.

### 2.3 One hardware SKU, designed for software evolution

We want a single PCB/board choice whose hardware capabilities exceed today's firmware needs, so that future functionality is a software problem:

- **Flash ≥ 8 MB** (dual OTA partitions need ~2× firmware size; current firmware uses GIF assets in LittleFS)
- **Screen** capable of the current UI (sprites, prompt text, status lines) — 1.14"–1.9" TFT class
- **At least two buttons** (approve/deny)
- **Addressable RGB LED(s)** for shell glow effects (current + future)
- **Dual-core ESP32-class MCU** with headroom for animation rendering

### 2.4 Volume: 100 units, sold to real customers

This is not a hobby batch. Selling to customers means:

- **Regulatory compliance is required** (FCC in the US, CE in the EU). See §6.
- **Consistency matters** — all 100 units should be the same hardware revision.
- **Someone must flash, test, and assemble** each unit. At this volume, that's us, with a simple test procedure.

### 2.5 Priorities: reliability first, functionality second, cost third

When options conflict, we choose the boring, proven, well-supported thing. A device that keeps working beats a device that does more.

### 2.6 Strategy: buy existing PCBs — do not design custom boards

**This is the key strategic decision.** We will always buy an existing, manufactured, ideally certified board and build our product (shell, firmware, packaging, experience) around it. We are explicitly *not* designing custom PCBs at current volumes, and we should not design for a future where we do until the volume forces it.

What this buys us:

- **Zero electrical engineering risk.** No schematic mistakes, no board spins, no EE hiring, no RF debugging.
- **Zero NRE (non-recurring engineering) cost** on the electronics. Our fixed costs go to the shell and firmware instead.
- **Speed.** We can have sellable hardware in weeks, not months.
- **Someone else's QC and revisions.** The board vendor eats manufacturing defects at the board level.

What it costs us (be honest about this):

- **Margin.** We pay retail-ish or light-bulk pricing (~$15–30/board) versus ~$10–15 for an equivalent custom PCBA at 1k+ volume.
- **Dependency and EOL risk.** The vendor can discontinue, revise, or reprice the board at any time. This is the single biggest reliability threat in this strategy and drives several mitigations below.
- **Fit constraints.** The shell must be designed around the board's dimensions, port placement, and screen position — not the other way around.
- **Certification gaps.** Not every hobby board is certified as an end product; putting a board in our shell and selling it makes *us* the responsible party. This is a major ranking criterion below.

**When to revisit this decision:** (a) sustained volume above ~1,000 units/year, where custom PCBA saves real money; (b) an EOL notice on our chosen board; or (c) a hardware feature we can't buy off the shelf. Even then, the first escalation isn't a from-scratch design — it's a simple carrier board around a pre-certified module (ESP32-S3-WROOM-1 or M5StampS3), which keeps radio certification and RF design out of scope. Full custom (bare chip, own antenna) should essentially never be on the table for this product.

---

## 3. Evaluation Criteria

Each option below is scored against, in priority order:

1. **Reliability** — vendor stability, QC track record, EOL risk, field failure surface
2. **Certification status** — is it legal to sell as-is, or how much testing do we owe?
3. **Firmware compatibility** — distance from our current M5Unified/M5GFX + LittleFS firmware
4. **Functionality fit** — screen, buttons, LED, flash size, BLE
5. **Assumption fit** — USB-C-only, one-SKU-forever, no custom PCB
6. **Unit economics** — landed cost at qty 100 and how it improves with volume

---

## 4. Top Three Options

### Option 1 (recommended for the first 100): M5StickC Plus 2, purchased in bulk, inside our custom shell

**What it is:** Buy ~115 M5StickC Plus 2 units (the exact device our firmware runs on today), design a shell that encloses it — exposing/relaying the screen, the A/B buttons, and USB-C — add our LED(s) driven from the Grove/GPIO port, flash our firmware, and sell the assembled product.

**Why it beats the alternatives for the first run:**

- **Zero firmware risk.** The firmware already runs on this exact hardware — screen driver, buttons, BLE stack, OTA, GIF rendering, all proven. Every other option requires a port with new bugs.
- **It's a finished, certified product.** M5Stack ships CE/FCC-marked devices. Selling a certified device inside a passive shell is the lowest-compliance-risk path available (verify the specific certifications on the current hardware revision before committing — see §6).
- **Integrated everything.** Screen, buttons, buzzer, IMU, RTC, BLE, USB-C in one tested unit. No inter-board connectors — connectors are a top field-failure source.
- **Vendor quality.** M5Stack is an established manufacturer (owned by a major industrial player) with real QC, not a hobbyist board shop.

**Downsides (real ones):**

- **It contains a 200 mAh lithium battery we don't want.** Violates the spirit of §2.1. Consequences: lithium shipping rules apply (UN3481, "battery contained in equipment" — manageable but real paperwork), the battery ages even unused, and it's a small thermal consideration in the shell. Mitigation: confirm with M5Stack whether a battery-less variant is possible in bulk (this conversation naturally leads to Option 2).
- **EOL risk is the big one.** M5Stack EOLs products regularly (several StampS3-based products are already EOL). If StickC Plus 2 is discontinued mid-run, we're stranded. Mitigations: buy the full production quantity up front (all ~115 at once, not just-in-time), get a written product-lifecycle statement from M5Stack sales, and treat Option 2 as the pre-negotiated successor.
- **Margin pressure.** Retail is ~$30; bulk direct pricing likely ~$20–25 (to be negotiated). With shell, LED, packaging, assembly labor, and compliance amortization, landed cost is roughly $35–50/unit. That sets a floor on retail price (~$79+ for healthy margins).
- **We're reselling someone's product.** The FCC/CE marks belong to M5Stack's device; our added LED and shell technically modify the system. Low practical risk with a passive shell and a simple GPIO LED, but we should get one compliance consult (~$1–2k) to confirm labeling requirements (the device's FCC ID must remain visible or be reproduced on our labeling).
- **Fixed 1.14" screen and their industrial design.** The shell has to work around their port and button placement.

**Unit economics at 100:** ~$20–25 board + $8–15 shell (resin/SLS printed at this volume) + $2–5 LED/packaging/misc + labor ≈ **$35–50 landed**.

**What changes as we scale:**

- **100 → 500:** Negotiate direct bulk pricing with M5Stack (they have a business sales channel). Get EOL commitments in writing. Move shell from 3D printing (~$10/unit) toward urethane casting or a shared-tool injection mold.
- **500 → 1,000+:** This option runs out of road. The battery, the margin ceiling, and EOL exposure all worsen with volume. The natural evolution is not custom PCBs — it's **converting this into Option 2** (M5Stack builds us a variant). Plan for that conversation to start well before we need it (lead time ~3–6 months).
- **Signal to move:** ordering more than ~250 units in a quarter, or any EOL/revision notice.

---

### Option 2 (recommended path to scale — start the conversation now): M5Stack ODM/semi-custom variant

**What it is:** M5Stack offers ODM services — they design and manufacture custom variants of their products for businesses. We'd ask for essentially "StickC Plus 2 minus battery, plus our LED(s), in our enclosure or a bare-board form for our shell," built on their existing electronics (StickC internals or an M5StampS3 module + their display stack).

**Why it's the right scaling destination:**

- **It keeps every advantage of Option 1** (proven electronics, their QC, their supply chain, M5Unified firmware compatibility) **while fixing its flaws**: the battery goes away, the industrial design becomes ours, EOL risk becomes a contractual matter instead of a hope, and unit cost drops because we're not paying for retail packaging and features we remove.
- **Still not a custom PCB in the sense we're avoiding.** They own the electrical design, the RF, the certification of the radio module, and the manufacturing. We specify requirements; we never touch a schematic. This is the maximal version of "buy an existing PCB."
- **One SKU forever becomes realistic.** A supply agreement with defined change control is how real products keep a stable hardware platform.

**Downsides:**

- **MOQ and NRE.** ODM deals typically want 500–1,000+ unit commitments and some tooling/setup fees ($5–20k range, to be quoted). Likely not available for the first 100 — which is exactly why Option 1 exists as the bridge.
- **Lead time.** Expect 3–6 months from first conversation to delivered units. Too slow for the first run.
- **Negotiation from weakness at low volume.** At 100 units we're a rounding error to them; the quote may be unattractive until we've proven sell-through.
- **Single-vendor concentration deepens.** Mitigated by contract terms (last-time-buy rights, design escrow if negotiable), but real.

**Unit economics:** unknown until quoted; plausible target is **$18–28 landed** at 1,000 units including enclosure if they do the full box build.

**What changes as we scale:**

- **Now (during the first 100):** Send the inquiry immediately, even though we'll build the first run as Option 1. The quote, MOQ, and lead time data de-risks the roadmap and may reveal a battery-less option sooner than expected.
- **~500–1,000 units:** Switch production here. First article inspection, agree on a test spec, and have them ship flashed-and-tested units.
- **5,000+:** Standard practice would be dual-sourcing or bringing a contract manufacturer into the mix; with this product's simplicity, staying single-source with strong contract terms is defensible.

---

### Option 3 (fallback / parallel evaluation): Waveshare ESP32-S3 LCD board in our shell (LilyGO T-Display S3 as alternate)

**What it is:** Buy an off-the-shelf ESP32-S3 development board with integrated display — primarily the Waveshare ESP32-S3-LCD family (e.g., the 1.47" ST7789-class boards with USB-C, onboard RGB LED, 16 MB flash, ~$12–15) or alternatively the LilyGO T-Display S3 (1.9" ST7789, two buttons, USB-C, ~$17–20) — port the firmware, and build the shell around it.

**Why it makes the top three:**

- **Best raw fit to our assumptions on paper.** No battery (genuinely USB-C-only, unlike Option 1), bigger screen options than the StickC, onboard addressable RGB LED on some Waveshare models (the shell light comes free), 16 MB flash for OTA headroom, ESP32-S3 (current-generation part with long availability runway).
- **Cheapest.** $12–20/board at qty 100 versus $20–25 for the StickC. Meaningfully better margins.
- **Escape hatch value.** If M5Stack pricing, EOL, or ODM terms go bad, this is the credible alternative — which alone justifies keeping a ported firmware branch alive on one of these boards.

**Why it's ranked third despite the better spec fit — the downsides dominate under a reliability-first priority:**

- **Certification is our problem.** These are sold as development boards, not end products. Their FCC/CE status as finished devices is inconsistent and often unverifiable. Selling them in our shell makes us the responsible party; we'd need our own compliance testing (~$2–5k if the radio module on the board carries modular approval, potentially much more if it doesn't). This erases much of the cost advantage at 100 units.
- **Hobby-board QC and silent revisions.** LilyGO in particular is known for board revisions that change pinouts or components without notice. Waveshare is more stable but still a dev-board vendor. A mid-production revision could break our firmware or shell fit. Mitigation (mandatory if chosen): buy all ~115 boards in one order from one batch, and incoming-inspect every unit.
- **Firmware port required.** Our firmware is built on M5Unified/M5GFX against StickC hardware. The port (LovyanGFX display config, button GPIO mapping, LED driver, buzzer removal/replacement) is 1–3 weeks of work plus a re-validation pass of every device feature: heartbeat rendering, approval flow, OTA, GIF playback, serial debug tools. Every ported feature is a fresh bug surface.
- **Missing pieces vs the StickC.** No buzzer, no RTC, no IMU on most candidates (we use the buzzer and RTC today; IMU is unused). Buttons on some Waveshare boards are boot/reset only — verify two *user* buttons exist or budget for adding them, which starts to violate the no-custom-hardware spirit.

**Unit economics at 100:** ~$12–20 board + $8–15 shell + $2–5 misc + higher amortized compliance ≈ **$30–45 landed** — about the same as Option 1 once compliance is amortized, with more risk. The cost advantage only materializes at higher volume.

**What changes as we scale:**

- **100 → 500:** Waveshare does bulk/OEM sales; pricing improves modestly. Compliance testing amortizes to near-zero per unit, so the board-cost advantage over Option 1 becomes real (~$8–10/unit better).
- **1,000+:** Same ceiling as Option 1 — at this volume the honest comparison is Waveshare-bulk versus M5Stack ODM, and ODM likely wins on total cost of ownership because certification, assembly, and supply risk are all someone else's job.
- **Signal to activate this option:** M5Stack EOLs the StickC Plus 2 without an acceptable ODM offer, or bulk StickC pricing comes in above ~$27/unit.

---

## 5. Options Considered and Rejected

- **Custom carrier PCB with an ESP32-S3-WROOM-1 module (JLCPCB turnkey assembly).** The strongest option in a world where we're willing to own electronics design: best margins at scale (~$10–20/unit assembled), exact-fit hardware, pre-certified radio module. Rejected because it violates §2.6 — it requires hiring an EE, 2–3 board revisions, owning RF/USB/power correctness, and owning all compliance. It remains the documented escape hatch if the buy-existing strategy ever fails structurally, and its existence is good negotiating leverage with M5Stack.
- **Fully custom PCB with a bare ESP32-S3 chip and our own antenna.** Rejected permanently at any plausible volume: RF layout expertise, antenna tuning, and full intentional-radiator certification ($10–20k+) for zero product benefit.
- **Generic unbranded AliExpress ESP32+LCD boards.** Cheapest per unit; rejected on every reliability axis — no revision control, no certification story, no vendor accountability.
- **Raspberry Pi / Linux-class hardware.** Massive overkill: cost, boot time, power, and OS maintenance burden for a device that renders sprites and two buttons.

---

## 6. Certification and Compliance (applies to all options)

We are selling a radio-containing electronic device to consumers. Minimum homework, in order:

1. **US (FCC):** If the board's radio module carries FCC modular approval (Espressif modules do; M5Stack finished products carry device-level marks), the radio is covered. The finished product still needs Part 15B unintentional-radiator testing (SDoC route, roughly $1–3k at a test lab) and correct labeling (FCC ID of the module/device visible per the grant conditions).
2. **EU (CE/RED):** Similar structure; a Declaration of Conformity built on the module's test reports plus EMC testing of the finished device. Decide early whether to ship to the EU in v1 — deferring CE to a second batch is a legitimate scope cut.
3. **Do one paid consult (~$1–2k) with a compliance lab before finalizing the option choice.** Specifically ask: (a) for Option 1, does enclosing a certified finished device plus adding a GPIO-driven LED require re-testing? (b) for Option 3, what exactly does the chosen board's module certification cover?
4. **Also:** RoHS documentation from the board vendor (usually available on request), and California Prop 65 labeling if selling into CA.

---

## 7. Execution Plan for the First 100 (Option 1)

1. **Procure:** Order 115 units (100 sellable + 15% for failures, debug units, and returns stock) in a single order from a single batch. Simultaneously send the ODM inquiry to M5Stack (Option 2) and buy 3 Waveshare/LilyGO candidates for a background port spike (Option 3 insurance).
2. **Compliance consult** (§6) in parallel with shell design.
3. **Shell:** Design around exact StickC Plus 2 dimensions; prototype via resin printing; 5–10 iterations expected. Include LED light-pipe/diffusor and a label area for regulatory marks.
4. **Firmware:** Freeze a production firmware tag. Add a serial-triggered self-test mode (screen pattern, button check, LED check, BLE advertise) — the existing `handleSerialCommand` debug path in `firmware/main.cpp` is the natural home.
5. **Production procedure per unit:** incoming visual inspection → flash production firmware over USB → run self-test → pair once with a test Mac and verify heartbeat + approve/deny + OTA check → assemble into shell → final visual → box. Write this as a one-page checklist; target <10 minutes/unit.
6. **Track serials.** Record each device's MAC/serial, firmware version, and test result in a spreadsheet. This is the seed of future support and RMA handling.
7. **Support plan:** decide return/replacement policy before selling (with 15 spare units, "we ship a replacement" is affordable and reliability-brand-building).

---

## 8. Decision Triggers Summary

| Trigger | Action |
|---|---|
| M5Stack bulk quote > ~$27/unit | Accelerate Option 3 evaluation |
| StickC Plus 2 EOL/revision notice | Execute last-time-buy; activate Option 2 or 3 |
| >250 units ordered in a quarter | Begin Option 2 (ODM) commercial negotiation in earnest |
| ODM MOQ/NRE unattractive at 1k units | Re-evaluate Option 3 at bulk pricing vs. the §5 carrier-board escape hatch |
| Hardware feature not buyable off-the-shelf | Revisit §2.6 strategy explicitly — do not drift into custom design |

---

## 9. Form Factor: The Blob

**Chosen direction.** A squishy, glowing, wobbling blob — a desk pet first, a gadget second. The design philosophy: spend nothing on complexity, spend everything on the three things people actually touch and see — the surface finish, the glow, and the wobble. Premium feel comes from weight, damping, and material honesty, not from features.

### 9.1 Shape and dimensions

- **Silhouette:** a squashed sphere / mochi profile — wider than tall, gently domed top, no neck, no limbs, no undercuts. One continuous convex surface. This is deliberately the cheapest possible geometry to print, cast, and eventually injection-mold (single parting line, generous draft everywhere), and it's also the most huggable.
- **Outer dimensions:** ~74 mm wide × 62 mm tall × 60 mm deep. Sized around the M5StickC Plus 2 (48.2 × 25.5 × 13.7 mm) mounted horizontally so the 1.14" screen sits landscape as the face, slightly above the blob's vertical midline (faces read cuter above center).
- **Bottom:** a spherical cap, radius ~48 mm — this is the wobble surface (see 9.4). No feet.
- **Screen window:** ~30 × 18 mm aperture with a flush 1 mm-recessed clear acrylic lens over the 25.9 × 14.6 mm active area. A ~2 mm dark bezel painted/printed on the lens underside hides the LCD's own bezel and makes the screen look edge-to-edge.
- **Wall thickness:** 2.0–2.5 mm in translucent material — thin enough to glow, thick enough to feel solid.

### 9.2 Color and finish

- **Base SKU: "Mochi" — warm off-white translucent frost** (think glutinous rice, not printer beige). The shell stays neutral because the LEDs supply all the color; a tinted shell would muddy the light language.
- **Finish is the premium lever.** Matte, slightly soft-touch frost. For SLA-printed shells: vapor polish inside (light transmission), fine bead-blast/sand outside (frost + fingerprint resistance). This finish work is ~$2/unit and is worth more to perceived quality than any added feature.
- **Blush cheeks:** two soft pink pad-printed dots (~$0.20/unit) flanking the screen. Optional but high-value cuteness per dollar.
- **Color variants later** are a tint change, not a tooling change — good merchandising with zero engineering.

### 9.3 Internal lighting

- **Hardware:** 2× WS2812B addressable RGB LEDs on a small strip, driven from the StickC's Grove port (keeps the board unmodified — important for §4 Option 1 compliance posture). One LED aims up into the dome; one aims down through a light-pipe ring in the base cup, throwing a soft halo on the desk around the blob.
- **Baffling:** a thin opaque baffle around the board so the LEDs light the shell, not the electronics silhouette. Shadowed internals ruin the glow effect; this is a $0.30 part that matters.
- **Light language** (all slow and soft — the blob should never feel like a notification LED):
  - Working: slow warm-white breathing (~4 s period)
  - Attention/approval needed: gentle amber pulse + desk halo on
  - Celebrate: a single green→warm ripple, then fade (not a rave)
  - Error: dim red heartbeat, low duty cycle — concern, not alarm
  - Idle: barely-there warm glow; Sleep: off
- Brightness auto-dims on a schedule (device has an RTC) and everything is disableable.

### 9.4 The wobble (boop mechanics)

The blob is a roly-poly (weeble): boop it and it wobbles back upright.

- **Physics:** with a spherical bottom, the blob self-rights when the center of mass sits below the sphere's center of curvature. We force this with a **steel disc (~40 mm × 6 mm, ~60 g) epoxied into the base cup**, keeping everything else light and high. Total device weight target 150–180 g — heft is also what makes it feel premium in hand.
- **Damping:** raw steel-on-desk wobbles too long and skates. A **cast TPU/silicone contact ring** (Shore ~60A) bonded to the bottom cap gives 2–3 damped rocks and then stillness, plus scratch/slip protection. Tune damping with ring width; target a "settles like a contented animal" feel, not a metronome.
- **Cable management:** USB-C must not fight the wobble. The cable exits high on the back through a molded strain-relief channel with a small service loop inside; ship a **right-angle braided cable in cream** in the box so the cord drapes instead of levering. (A cheap straight cable poking out the back would kill both the wobble and the premium feel — this $3 cable is where "cheap where it counts" does NOT apply.)
- **The payoff:** the wobble is also an *input*. The StickC Plus 2 has an onboard IMU (MPU6886), so the firmware can detect boops, shakes, and pick-ups for free — see §10.

### 9.5 Mechanical architecture and assembly

Three-part stack, no visible fasteners:

1. **Translucent outer shell** (the blob body) — one piece, drops over everything.
2. **Internal chassis** — printed frame that clips the StickC board, LED strip, baffle, and lens; locates the screen against the window and routes the top-button plunger.
3. **Base cup** — carries the steel weight, TPU ring, buzzer grille holes, deny button, and USB-C channel; twist-locks or screws into the chassis from below, hidden under the TPU ring.

The **squish top** is a molded silicone cap (Shore ~30A, ~25 mm dome) seated in the shell's crown, driving a plunger onto the board's A button. Travel ~2 mm with a soft bottom-out — it should feel like pressing a marshmallow that clicks. At 100 units this is a cast-silicone part (~$3–5/unit from a small-batch molder); at volume it becomes an LSR/compression-molded part (~$1–3k tool, <$0.50/unit).

### 9.6 Materials and process by volume

| Volume | Shell | Squish cap | Base/chassis | Notes |
|---|---|---|---|---|
| 10 (prototypes) | SLA clear resin, hand-frosted | Cast silicone, 3D-printed mold | SLA | Iterate wobble weight + damping here |
| 100 (first run) | SLA translucent via print service, bead-blasted | Cast silicone, machined mold | SLA/SLS | ~$15–20/unit total printed parts |
| 1,000+ | Injection-molded translucent PC or PP frost ($6–12k tool) | LSR or compression mold | Injection ABS | Shell unit cost drops under $2 |

The blob's geometry was chosen so that **nothing about the design changes between these stages** — same parting line, same assembly, same look. Only the process gets cheaper.

### 9.7 Example unit cost at 100 (supersedes the §4 ballpark)

| Item | Est. cost |
|---|---|
| M5StickC Plus 2 (bulk) | $20–25 |
| Printed shell + frost finish | $10–15 |
| Silicone squish cap | $3–5 |
| Base cup, steel weight, TPU ring | $3–4 |
| 2× WS2812 + Grove cable + baffle | $2–3 |
| Lens + fasteners + adhesives | $2 |
| Packaging (box, insert, braided right-angle cable, adoption card) | $5–8 |
| Assembly + flash + test labor (~15 min/unit) | $8–10 |
| **Landed total** | **~$55–75** |

At 1,000 units (injection tooling + M5Stack ODM board per §4 Option 2): **~$25–35 landed**. The 100-unit run is margin-thin by design — it's buying learning, not profit. Suggested retail given this BOM: $99–129, positioned as a premium desk companion, not a gadget accessory.

---

## 10. Interactions and User Flows

> Note (2026-07-25): this section describes the Blob (M5StickC) concept. The
> production Pebble's detailed end-state UX — face-first screen, halo light
> language, three-button grammar, IMU gestures — is specified in `PEBBLE-UX.md`,
> which supersedes this section where they differ.

Design principles: **two buttons, ever.** Every input maps to a caretaking gesture, not a UI action. The device is a pet you tend, and tending your pet happens to run your agents. Fun is carried by small details — animation timing, sound character, damped physics — not by feature count.

### 10.1 The input vocabulary

| Input | Hardware | Meaning |
|---|---|---|
| **Pet** (squish the top) | Silicone cap → A button | Yes / approve / acknowledge — the affirmative gesture is literally petting your buddy |
| **Boop** (poke the body) | IMU wobble detection, no button | Playful acknowledge / dismiss / "I see you" |
| **Hold** (squish 3 s) | A button long-press | Sleep/wake toggle (quiet hours) |
| **Deny** | Recessed plunger on the back → onboard Button B | No / deny — deliberately requires reaching around: denial should carry a beat of intention, approval should be frictionless |
| **Pick up** | IMU | Blob dangles its expression, shows a session summary while airborne |

**No added electronics.** The StickC Plus 2 ships with two user buttons: Button A (large, front face) and Button B (narrow edge). Both shell inputs are dumb plastic parts that press them: the squish cap drives a small printed lever that converts the vertical squish into a forward press on front-facing Button A, and the deny plunger passes straight through the base to edge-facing Button B. If a future interaction ever truly needs a third input, the Grove port accepts a $0.50 button breakout — but per the two-buttons-ever rule, it shouldn't.

**Boop sensing, honestly.** The IMU cannot distinguish a boop from a desk bump, a dropped mug, or vigorous typing nearby. That's fine *because boops are only ever mapped to safe, reversible actions* — wake, dismiss, giggle. A false boop at worst dismisses a celebration early or makes the blob giggle unprompted (arguably a feature). Approve/deny require mechanical button presses for exactly this reason and must never be gesture-triggered. Pick-up detection (sustained tilt + acceleration, distinct from rocking) is more reliable but follows the same rule: display-only effects.

Why not more buttons: every additional control turns the pet back into a device. Anything needing more input than yes/no/boop belongs in the Mac popover, which is always within reach anyway. Why not fewer (zero-button, boop-to-approve): approvals gate real agent actions with side effects — they need a positive mechanical press, not an accelerometer guess. Boops are for affection and dismissal precisely because they're low-stakes.

### 10.2 Core flows

**Approval (the hero flow).** Agent requests permission → blob's desk halo fades in amber, face looks up expectantly with a compact tool line ("Claude wants to run `npm test`"), one soft "meep?" chirp. You reach over and **pet it** → the cap squishes, the blob closes its eyes into a happy squint, a green ripple runs through the shell, a two-note affirmative chirp plays, and the agent unblocks — total time, under a second, without touching your keyboard or switching windows. To refuse: press the back button → the blob gives a solemn little nod, brief dim-red blink, done. No guilt animation; denying should feel responsible, not mean.

**Completion.** Task finishes (≥30 s of work) → confetti-pixel celebrate face, shell ripple, a short ascending trill. The celebrate face *persists* as a subtle "gift waiting" expression until you **boop it** — the blob wobbles, giggle-chirps, and settles back to idle. This turns "your agent finished" into a tiny reward you collect, which is the gamification loop in its cheapest possible form.

**Long work / stall / error.** While busy: focused face, breathing glow, occasional tiny "effort" animations. Gone quiet past the stall threshold: thinking face with a drifting "…" bubble — calm, explicitly not an alarm. Explicit failure: dizzy face, dim red heartbeat, one low "oof" note. An error stays until booped (acknowledge) — then the blob shakes it off, literally.

**Idle affection (the retention loop).** At idle the blob blinks, glances around occasionally, and reacts to a boop *any time* with a wobble + giggle + brief heart-eyes. Boop a *sleeping* blob and it stirs, peeks with one eye, and dozes back off — sleep is never a wall, just a mood. It never asks for anything — no hunger nags, no guilt mechanics — but it always responds. The joy has to be free or it becomes a chore. Deeper gamification (streaks, growth, accessories) lives in the Mac popover; the blob just *wears* the results (a crown sprite after a productive week, a plumper idle face).

**Plug-in / wake.** First power of the day: a wake-up stretch animation and a yawn chirp. First-ever boot: a hatching sequence (egg → crack → blob) — this is the unboxing moment people post about, and it costs only firmware.

### 10.3 Sound character

The buzzer (already on the board) is the right instrument: chiptune chirps read as "creature," not "appliance." Rules: nothing longer than 3 notes except celebrate; every event has a distinct motif (attention = rising "meep?", approve = two-note "mm-hm!", celebrate = 5-note trill, error = single low "oof"); hard volume cap; global mute honored everywhere; auto-quiet during sleep hours. A real speaker stays a v2 Grove add-on — better sounds are not what v1 needs.

### 10.4 Premium in the details (cheap where it counts)

Where the money goes: surface finish, silicone cap feel, steel heft, damped TPU wobble ring, braided right-angle cable, edge-to-edge lens. Where it doesn't: no extra buttons, no speaker, no touchscreen, no mic, no battery, no app beyond the existing Mac app. Packaging leans on the pet fiction — an "adoption box" with a die-cut window, care-instructions card written in-universe, and the serial number as an "adoption ID." Cardboard and copywriting are nearly free; they do the emotional work of $20 of hardware.

### 10.5 Firmware implications (all software, no new hardware)

- IMU boop/shake/pick-up detection with debounce tuned against the wobble's natural motion (the wobble itself must not self-trigger dismissals).
- Face/expression sprite set for: sleep, idle (+blink variants), busy, thinking, attention, celebrate (+persistent gift-waiting), error, boop-react, pick-up dangle, hatch, wake-stretch.
- WS2812 driver on the Grove pins + the light-language state machine mirroring `RenderState`.
- Long-press sleep mode; scheduled quiet hours via RTC.
- These map cleanly onto the existing heartbeat contract — the Mac app already sends state, prompt, and completion metadata; the blob decides how to *feel* about it.

---

## 11. Positioning, Marketing, and Launch

### 11.1 Why people buy things (the principles we're applying)

Purchases like this one are decided emotionally and defended rationally. The buyer falls for the wobble in a 6-second video; then they need a *rational alibi* to justify $99 — and ours is unusually strong ("it approves my agents' tool calls without breaking my flow"). The marketing job is therefore two-layered: lead with the emotion, hand them the alibi. Never reverse the order — a features-first pitch ("multi-agent approval surface with BLE") makes it a gadget competing on specs, and it loses that fight.

The other principles doing work here:

- **Identity purchase.** Nobody needs a desk pet. People buy what signals who they are — and "I run AI agents all day, and I've made peace with it, playfully" is a fresh identity with no incumbent product expressing it. The blob on a desk in the background of a stream or a video call *is* the ad.
- **Kano delight.** Basic features satisfy; unexpected ones delight and get retold. The wobble, the sleeping peek, the hatching — these exist to be *described to a coworker*. Word-of-mouth is compressed delight.
- **Scarcity and story beat reach.** 100 units cannot support paid acquisition math and shouldn't try. A numbered first batch converts our smallness from weakness to mechanic.
- **Price is positioning.** $99–129 with premium finish, heft, and packaging reads "considered object" (Teenage Engineering territory). $39 with the same electronics would read "Aliexpress trinket." Given our BOM (§9.7), the premium price isn't greed — it's the only honest position.
- **Gifting doubles the market.** "Perfect gift for the engineer in your life" is a real, underserved query space, and the adoption-box packaging is already built for it. Gift buyers don't compare specs; they buy story and photography.

### 11.2 Positioning statement

**For developers who run AI coding agents, Boop is a desk companion that turns invisible agent work into a creature you can see, hear, and pet — so the moments that need you feel like caring for a pet, not clearing notifications.** Unlike menu bar utilities and dashboards, it lives in physical space; unlike desk toys, it does real work (approve/deny, status, completion). Category label to own: **desk companion for AI agents** — we should name the category before someone else does.

Tone: warm, wry, understated, in-universe where possible. Banned vocabulary: "revolutionary," "AI-powered," "productivity," "supercharge." The product is confident enough to undersell.

### 11.3 Messaging

Hero line candidates (test on the waitlist page):

- "Your agents, with a face."
- "Approve with a pet." *(double meaning is the brand in three words)*
- "It wobbles while you work."
- "The little creature that watches your agents."

Supporting messages, in priority order: (1) *pet to approve* — the hero interaction, always shown not told; (2) *glanceable calm* — amber glow means you're needed, otherwise it just vibes; (3) *it's alive* — boops, wobbles, naps, celebrations; (4) the alibi — works with Claude Code, Cursor, and Codex, local-first, no cloud. Note the alibi includes a real trust point: everything runs on localhost, which this audience genuinely cares about.

### 11.4 Landing page direction (principles, not a spec)

One product, one page, film-first. Hero: a single continuous loop — blob idling on a real wooden desk, glow shifts amber, "meep?", a hand reaches in and pets it, green ripple, hand returns to keyboard. No text over the video beyond the hero line and "Adopt one." Below the fold, in order: the approval flow explained in three stills; the light language; the wobble (loop, 3 seconds, autoplay); the adoption box; compatibility row (Claude Code / Cursor / Codex logos — borrowed credibility); founding-batch counter ("37 of 100 remaining"). Design language: enormous whitespace, cream/warm palette matching the shell, real photography over renders, prices and shipping stated plainly. Premium on the web is restraint — every extra section erodes it.

### 11.5 Launch and channels for the first 100

Paid ads are the wrong tool at this volume — CAC would exceed margin, and scarcity does the work for free. Sequence:

1. **Build in public** (X/Twitter, threads with wobble videos and shell prototypes) starting now — the manufacturing journey itself is content this audience loves, and it compounds into launch-day distribution.
2. **Waitlist page** live before units exist; the hero-line A/B happens here.
3. **Show HN / launch post** written as an engineering story ("I turned my agents' permission prompts into a pet you boop"), not a product announcement. HN forgives selling if the writeup teaches something — the wobble physics and the buy-not-build PCB strategy are both genuinely teachable.
4. **Seed 5–10 units** to desk-setup and dev-tools creators (YouTube desk tours, r/battlestations, coding streamers) — a blob visible in one popular desk tour outperforms any ad we could buy.
5. **Drop mechanics:** the 100 are the "Founding Litter," numbered adoption IDs, small print run of extras (sticker, care card). Sell out fast on purpose; the waitlist for batch two is the real asset the launch produces.

### 11.6 What the ads look like (for later batches, when paid makes sense)

Video-first and interaction-led: the 6-second pet-to-approve loop is the entire creative — no VO, no feature list, caption "Approve with a pet." Static variant: blob glowing amber on a dark desk, screen reading "Claude wants to run `npm test`," caption "You know what to do." Formats native to the feed (vertical loops), targeted by developer-culture interest graphs, not job titles. The creative rule for everything: **show the interaction, never describe the product.**

### 11.7 SEO, honestly scoped

At 100 units, SEO is a batch-three concern; search compounds too slowly to sell a founding run. What's worth doing now because it's nearly free: own the brand terms — adoptaboop.com is registered; the indexable brand term is the *lockup* ("Boop Computer," "boop pet"), never bare "boop," which belongs to Betty Boop and the memes (MARKETING.md §1.5) — make the build-in-public posts live on our own domain (they become the long-tail corpus), and hold the category phrase "desk companion for AI agents" in page titles so we're the definitional result when the category query starts existing. Later, the two real query spaces are gift-intent ("gift for programmer who has everything") and category-intent ("AI agent desk toy/companion") — both currently weak-competition. Skip keyword-stuffed blog content entirely; it would poison the premium brand for pennies.

### 11.8 Name decision (2026-07-04)

The product is **Boop**; the company is **Boop Computer**; the site is **adoptaboop.com** (contact: hello@adoptaboop.com). The creature is "a boop" (plural "boops"); "buddy" remains the in-universe common noun ("adopt a buddy"). The gesture vocabulary (§10.1) is unchanged — pet = approve, boop = hello/dismiss — and resolves into the naming line: **"Boop it to say hi. Pet it to say yes."** Rationale, findability rules, and the Betty Boop trademark caution live in MARKETING.md §1.5. "Buddygotchi" persists only as the internal repo codename and must not appear on customer-facing surfaces.

---

## 12. Surviving the Agent Evolution (Apps, Auto-Approve, and the Durable Value Prop)

The agent landscape is shifting under us in two ways: people code across a growing set of surfaces (CLIs, desktop apps, IDE extensions, cloud agents), and they're moving from approving individual tool calls to setting goals and auto-approving everything. This section is the plan for both.

### 12.1 The full surface matrix

Checked against the mid-2026 landscape, the hook story is better than feared: the industry has converged on Claude-Code-style lifecycle hooks. Claude Code, Codex, Cursor, and VS Code Copilot all expose them now. The real dividing line is not "CLI vs app" — it's **local agent runtimes vs chat-style and cloud surfaces.**

| Surface | Signal available | Boop status |
|---|---|---|
| Claude Code CLI | Full hooks (`~/.claude/settings.json`) | **Works today** — current integration |
| Claude Code desktop app | Same settings.json tree as CLI; hooks apply uniformly | **Works with existing install** — verify on macOS (a Windows-specific no-fire bug is reported) |
| Claude Code IDE extension (VS Code / JetBrains) | Same settings.json tree | **Works with existing install** — verify |
| Claude app (Cowork) | No hooks fire (open requests #63360, #47993); coarse session info only | Tier 3 watcher for now; adopt first-party hooks the day they ship |
| Codex CLI | Stable hooks engine since v0.124 (Apr 2026): SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, Stop; `hooks.json` or `config.toml` | **Works today** — current `~/.codex/hooks.json` integration matches |
| Codex desktop app | All Codex surfaces are thin clients on one App Server that owns thread lifecycle and runs hooks | **Should work with existing install** — but hook regressions have shipped in desktop alphas; put it in the release-test matrix |
| Codex VS Code extension | Same App Server | Same as desktop — verify per release |
| Cursor | Richest hook set (`~/.cursor/hooks.json`) | **Works today** — current integration |
| VS Code Copilot agent mode (preview) | Reads hook configs from the same `.claude/settings.json` files, tracking Claude Code's event vocabulary | **Likely works nearly free** via our existing Claude Code install — verify, then add a Copilot source badge |
| GitHub Copilot CLI | Claude-style hooks | Small adapter; reuses the same bash hook script |
| Cloud-executed agents (Codex Remote/web, Copilot cloud agents, Claude Code web) | Run on remote machines — local hooks never fire | Out of scope for v1; see §12.4 |

Three implications worth underlining:

1. **Our three config writes already cover ~seven surfaces.** Because Claude Code's desktop app and IDE extensions share the CLI's settings tree, and Codex's surfaces share one App Server, the existing installer (Claude settings.json + Cursor hooks.json + Codex hooks.json) covers the CLIs, both desktop apps, and the IDE extensions without new code. The work is *verification*, not integration.
2. **VS Code Copilot may be a free fourth agent.** Its preview agent-hooks feature reads the same files with the same event names we already install for Claude Code. If that holds up in testing, "works with Copilot" is a marketing line that costs a badge sprite.
3. **The chat-style and cloud surfaces are the real gaps** (Cowork today, cloud agents structurally). For these, the fallback tiers apply — and the pet must degrade gracefully to a two-signal world (working, done) and still be lovable. Attention/approval richness is bonus, never a requirement.

**Fallback tiers** for surfaces without hooks, all mapping onto the same `BuddyEvent` vocabulary through `HookServer`: **Tier 2 — coarse events** (e.g., Codex's `notify` turn-complete as a belt-and-suspenders channel alongside hooks; a tiny adapter POSTs to `/hook/event`); **Tier 3 — inference** (a host-side watcher tails session transcripts — `~/.claude/projects` JSONL, Codex session logs — and derives working / gone-quiet / done from file activity; laggy but universal).

**One-click setup implications.** The setup wizard already detects and installs the three config files; extend it with per-surface detection rows (cosmetic — the install is the same file), a Copilot toggle once verified, and a "test connection" step that names the surface it heard from ("Heard from Codex (desktop)!") — that last detail turns an invisible config write into a moment of delight and doubles as the per-surface smoke test.

**Engineering guardrails.** (1) Per-surface e2e smoke tests: `app/tools/e2e/` covers the CLIs today; add desktop-app and extension variants and run the matrix before each release. (2) Hooks fail open everywhere (already policy) — a surface that silently stops firing degrades to a sleeping pet, never a broken agent. (3) Keep a version-compat note in the repo tracking known-good agent versions; agent apps ship weekly and hook regressions have already happened in the wild (Codex desktop alphas). The blob's reliability reputation depends on us catching their regressions before users do.

### 12.2 Is there a value prop when everything is auto-approved?

Yes — and it's arguably stronger. The approval flow is the *wedge*, not the foundation. What the product actually sells is **attention orchestration**, and auto-approve makes attention *more* mismanaged, not less:

- **The scarce thing shifts from decisions to re-engagement.** In the goal-setting world you have N agents running across tabs and terminals, finishing asynchronously. The failure mode is no longer "agent blocked on my approval" — it's "the task finished 22 minutes ago and I'm still doom-scrolling because nothing told me." The blob's celebrate-until-booped state is precisely this: a physical, glanceable "come back" that doesn't require checking anything. The user's own instinct — "the blob shows up and oh, I need to switch back to this task" — is the v2 hero flow.
- **Exceptions get rarer and higher-stakes.** Even full-auto agents still stall, fail, and occasionally need a human decision (elicitation, conflicts, credentials). When interruptions drop from twenty a day to two, each one matters more — and a soft amber glow in peripheral vision beats notification #47 in a pile of Slack pings. The blob becomes the *only* channel that never gets buried.
- **Visibility is what makes delegation emotionally safe.** People auto-approve but still feel low-grade anxiety about what the agent is doing. Ambient presence — it's breathing, it's working, it's fine — is the trust layer that lets people delegate more. That's a value prop that grows with agent autonomy.
- **The emotional core doesn't depend on approvals at all.** Companionship, the wobble, collecting completions, the celebration trill — none of it required a permission prompt. The pet was never really an approval device; it was a relationship with your work.

The state vocabulary (sleep / idle / busy / thinking / attention / error / celebrate) is agent-paradigm-agnostic — it described human-in-the-loop coding in 2025 and it describes fleet supervision equally well. The **pet gesture's meaning migrates gracefully**: today it's "approve"; tomorrow it's "acknowledge / confirm the plan / send it." A yes-shaped physical button never goes out of date.

### 12.3 The one-time-purchase promise

The hardware is deliberately a generic terminal — screen, two buttons, glow, IMU, BLE — with all semantics living in the Mac app and OTA-updatable firmware. That's not just an engineering choice; it's the marketing message that answers "will this be obsolete in a year?":

> **Buy it once. It keeps up.** No subscription. When the agents change, your buddy learns the new tricks in a free update.

Free updates on a subscription-free device are affordable because updates are cheap (adapters are small) and each one is a re-engagement and word-of-mouth event ("my blob just learned to watch the Codex app").

### 12.4 Marketing across the eras

- **Era 1 (now, human-in-the-loop):** "Approve with a pet." Hero flow: amber glow → pet → agent unblocks.
- **Era 2 (auto-approve, multi-agent):** "It watches your agents so you don't have to." / "Know when to come back." Hero flow: you're reading something else → green ripple + trill → boop → switch tasks. Secondary: the fleet view — one calm creature summarizing five running agents.
- **Constant across both:** the identity purchase (§11.1) and the emotional layer don't change at all — only the rational alibi updates. The brand never needs to pivot; the landing page swaps one section.

The honest risk to monitor: a world where agents run entirely in the cloud, detached from a desk or a Mac (delegation from a phone, agents-as-a-service). The mitigation is the same architecture seam — the Mac app is just the current *brain*; a future brain could subscribe to cloud agent APIs and drive the same BLE contract. Track it; don't build it yet.

---

## 13. Open Questions

- Trademark clearance for "Boop" (classes 9/28) against Fleischer Studios' BOOP!® registrations — a launch gate; engage counsel before announcing the name publicly.
- Hosting for the Sparkle appcast and firmware manifest at adoptaboop.com (`/releases/appcast.xml`, `/firmware/manifest.json`) plus hello@ email forwarding — the Mac app now points at these URLs.
- Exact current certification marks on the shipping M5StickC Plus 2 revision (verify against FCC ID database and M5Stack docs).
- M5Stack bulk pricing, lifecycle commitment, and ODM MOQ/NRE/lead-time (blocked on sending the inquiry).
- EU shipping in v1, or US-only first batch.
- Target retail price (drives how hard to negotiate the board cost) — §9.7 suggests $99–129.
- Wobble tuning: steel weight mass and TPU ring durometer need physical prototyping (plan 3–4 base-cup iterations).
- Silicone cap small-batch molder selection and unit pricing at 100.
- Whether the A-button plunger can reach the StickC's button without opening the case (strong preference: keep the device unmodified; the StickC's front button placement should allow a direct plunger).
- Screen orientation: confirm landscape rotation of the current firmware face renderer.
