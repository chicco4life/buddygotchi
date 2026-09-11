# Consecutive-frame webcam review

The user explicitly requested webcam verification and confirmed this session’s
physical setup. Four bounded six-second video-only clips used the MacBook Air
camera, unchanged framing, and isolated USB-only firmware. No microphone or
background capture was used. Original room footage remains under
`/tmp/boop-quality-device`; only selected screen crops are retained here.

The first candidate is identified by `/tmp/boop-quality-device/firmware.bin` and
its SHA-256 in `candidate-identities.json`; its embedded label is
`dev+6182f51882a7` / board `ws-amoled164`. The footer follow-up has a separate
binary identity and clip; do not attribute these earlier clips to that binary.

## Method and capture quality

Reviewed **every consecutive image** in all six sheets per clip, including
onset and settling. This was image-sequence inspection, **not real-time video
playback**. The actual decoded interval is about 5.10 seconds per requested
six-second clip. Greet has 154 frames; working, dance and card have 153. Median
cadence is about 33.34 ms. The latter three have one 66.67 ms interval at
5.034 seconds, after the reviewed transitions have settled. No smoothness claim
covers that gap. Reports and per-frame timestamps are beside the selected crops.

The screen is fully framed and gross motion is visible. White eyes bloom;
small text and fine edges are soft. The physical screen is landscape. Some
frames contain partial scanning/banding, particularly state transitions and
bright eyes. These are not enough evidence to assign a firmware tearing fault.
Camera FPS does not establish device FPS. Fine pixel-level smoothness is
inconclusive with this exposure/focus; deterministic screenshots and USB pose
samples independently cover layout and interruption behavior.

## Observations

- **Working, limited pass:** the entry blink begins around 0.70 s, narrows
  through 0.80 s and opens by roughly 1.0 s. The face remains stable afterward;
  no repeated jumps were visible. This short clip does not cover the entire
  long working-gaze cycle.
- **Greeting, limited pass:** visible onset around 0.70 s, one rising heart and
  a raised waving arm. The heart disappears around 1.7 s; waving continues
  through roughly 2.9 s and retracts toward rest through 3.1 s. No downward arm
  flip was visible. Idle remains stable through the end.
- **Dance, limited pass:** visible onset around 0.63–0.67 s, alternating sway
  and arms with a small particle group. Motion winds down near 3.17 s and
  settles into the done smile by about 3.4 s. This is consistent with the
  2.5-second dance plus pose settling within camera quantization. No abrupt
  level-head snap was visible at the end.
- **Initial card, issue found:** card arrival begins around 0.67–0.70 s and
  settles by about 1.0 s. On host removal around 2.17–2.20 s the footer text
  vanishes immediately while the face continues easing. This prompted the
  presentation-only retained footer fix. Follow-up verification is recorded below.

These observations cover the named controlled scenarios only. They do not
certify every animation or production BLE behavior. Earlier basic idle/blink
setup verification remains local under `/tmp/boop-webcam-check-20260911-retry`.

## Footer follow-up — final candidate

Reviewed all 153 consecutive frames (all six sheets) in the final six-second
requested clip, using the same camera and screen crop. Actual duration is
5.10059 s, median interval 33.34 ms, with one 66.67 ms gap after 5.03392 s;
that gap is well after settling. Eye bloom is stronger in this clip, so do not
interpret the brightness difference as a product change. No real-time playback.

**Limited pass:** arrival starts around 0.60–0.63 s and settles by about 0.9 s.
After removal around 2.17 s, “Question” remains visible lower in the footer at
2.20 s and leaves the bottom edge around 2.23 s, while the last rule and face
continue settling. By roughly 2.6 s the idle view is stable and the footer does
not return. This closes the abrupt text-disappearance issue observed in the
initial clip. Fine scan artifacts and pixel-level smoothness remain inconclusive
with this camera setup. See `card-final/sequence-002.png`; full sequences and
original footage remain local under `/tmp/boop-quality-footer`.
