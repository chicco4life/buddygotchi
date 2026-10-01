# Animation / mood design publication

Updated 2026-09-28. User-authorized new-branch push of the completed local
animation work and mood-graph handover. No PR, merge, deployment, paid voice
generation or production integration is part of this change.

Scope: [internal/boop-design](../../../internal/boop-design/README.md).
Imported from the validated V4 design bank and V2 mood graph, preserving the
existing performances. Full SVGs are reproducible with the documented
`--svg` export; procedural sound is stored as code, not recordings.

Evidence files beside this document contain the rerun graph, structural/audio
and browser results, plus a direct scene-and-score comparison between the
repository import and the source review bank. Browser dependency paths are
provided through environment overrides; the committed code has no
workstation-specific paths. No source animation changes were made during
repository packaging.

The original checkout's uncommitted animation-review, voice-plan and related
documentation changes were excluded and left intact. This isolated branch
starts at remote main commit `7059294`; no commits from a separate working
branch were included.

Not run: firmware generation/flashing, Bluetooth, webcam, production pipeline
or JEV evals, or ElevenLabs. No production code changed. Review candidates
remain review candidates; passing browser tests is not subjective visual or
audio acceptance.

Results: all 770 imported SVGs and sound scores matched the source review
bank; all 308 older fingerprints passed; all 462 new scenes passed browser
parsing, timing and cue checks, with 103 representative raster seams/text
lanes checked. All 770 SVG selections exported successfully. All edited
Markdown links resolved; the five scripts' help commands, source-path scan,
mirrored instruction-file comparison and staged whitespace check passed.

Pre-existing documentation drift noted but not changed: VISION uses both
six and seven for mood counts, while the current Mood action offers six
and the art bank has seven. The design handover explicitly distinguishes
those inventories and the proposed expanded graph.
