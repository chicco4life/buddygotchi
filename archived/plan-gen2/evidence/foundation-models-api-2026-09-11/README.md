# Foundation Models API review — 2026-09-11

The production runtime uses `SystemLanguageModel.default`, a fresh session,
the complete behavior guide as instructions, raw string output and temperature
0.4. It already separates trusted instructions from context data. No production
runtime or guide changed during this investigation.

## Apple guidance

- [Prompting an on-device model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model): prefer focused, concise requests; customize conditional instructions to the active task; reduce reasoning burden; start with one request before adding multiple calls and latency.
- [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation): use typed output or dynamic schemas for structural constraints. Properties are generated in declaration order. This guarantees structure, not semantic accuracy.
- [Generation options](https://developer.apple.com/documentation/foundationmodels/generationoptions): a hard response-token ceiling can truncate or damage output; it is not a substitute for a correct title or byte validation.

## Bounded local experiment

`trial.swift` compares focused raw generation with focused dynamic-schema
generation. Both use temperature 0.4 and the same synthetic inputs. The guided
schema requires one purpose field per input project and a combined title, all in
one request. Input count selects fields; the model still chooses the purposes.
The standalone command-line toolchain lacked the `@Generable` macro plugin, so
the experiment uses Apple's documented `DynamicGenerationSchema` API instead.

Inputs include the previous one-project and two-project failures plus a new
garden-planner/piano-practice example. `repeat.swift` repeats guided generation
three more times per input. Reproduce with:

```sh
swift plan/evidence/foundation-models-api-2026-09-11/trial.swift plan/evidence/foundation-models-api-2026-09-11/inputs.json
swift plan/evidence/foundation-models-api-2026-09-11/repeat.swift plan/evidence/foundation-models-api-2026-09-11/repeats.json
```

All twelve guided responses returned a structure and a title below 120 bytes,
in approximately 0.54–1.01 seconds. All four website cases included the website
in the final title, and all four garden/piano cases mentioned both domains.
The raw two-project response still included an unwanted note about byte length.
Example guided result: “Device and Website Layout Improvement”.

This is promising, **not a production semantic-quality pass**. Several purpose
fields narrow Boop's work to device layout/animation, omitting the Mac/settings
aspects. Garden-planner software work sometimes becomes actual gardening work.
Only three synthetic inputs and four guided samples per input were tested.
No memory, sparse-context, stale-intent, injection, many-project, dialogue or
production cancellation/deadline tests are covered. Timings are standalone
observations, not an app performance guarantee. The two experimental changes
(focused instructions and guided output) are not fully isolated from each other.

## Recommended next implementation

Keep one editable Markdown behavior source, but select the active occasion's
instructions plus common boundaries instead of sending unrelated operations.
Owner clarification: every message is optional. Any adopted schema must support
an explicit silent outcome, without forcing a populated message. Confidence
means grounded, useful content; do not gate on an uncalibrated model self-score.
Use a single structured generation with project-purpose fields before the title;
retain byte validation, cancellation, deadline and silence behavior. Required
fields make omissions easier to inspect, but neither presence nor schema validity
proves the final title faithfully covers the work. Expand the semantic fixtures
before adopting the change. Update architecture/behavior specs with that change;
do not silently add multiple model stages or hard-coded semantic categories.
