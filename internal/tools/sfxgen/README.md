# sfxgen

Builds `firmware/assets/sfx.h`, Boop's sound effects, from the animation
pack's procedural sounds ([plan/VOICE.md](../../../plan/VOICE.md) §10):

    node internal/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]

`pack/` is from the pack's 2026-09-28 release (V2): its synthesiser and
recipes (`pack/audio/`, unchanged) and the timelines of the states the
device draws (`pack/scores/`; the pack's `listening` is left out). The
designs themselves are in `../facegen/design/`. To take a new release,
replace both and rerun this and `make -C internal faces`.
