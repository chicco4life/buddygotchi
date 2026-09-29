"""Builds Boop's voice (plan/VOICE.md §3) from the recorded voice bank.

The bank, internal/boop-design/assets/boop-voice-v1/, has whole recorded
takes, each a word, a sound, a phrase or a swear performed in one mood.
Every take in its manifest is converted from its robot-soft WAV (44.1 kHz,
16-bit): the near-silence around it trimmed, cut to 11.025 kHz with a box
low-pass, saturated and normalised like the old syllables so it's as loud
on the small speaker, and stored as 8-bit unsigned samples. Two files come
out, both checked in; rerun this only when the bank or a mapping changes:

    python3 internal/tools/voicegen/voicegen.py [--wav-dir DIR]

- firmware/assets/voice.h: each take's samples, its bubble text and its
  mouth (open or shut every 20 ms), which the board plays by id.
- app/BoopKit/Voice/Takes.swift: each take's id, text, meaning, kind, mood,
  the finish it needs and its length, which the Mac picks from.

The bank's intents are the meanings Jev picks from (harness/DECISIONS.md
§3), its category the kind. Six takes were recorded in moods Boop doesn't
have; MOOD_OF gives them one, by the owner's word (2026-09-29).

`--wav-dir` also writes every converted take as a WAV, for listening.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import wave
from array import array
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BANK = REPO / "internal" / "boop-design" / "assets" / "boop-voice-v1"
OUT = REPO / "firmware" / "assets" / "voice.h"
SWIFT = REPO / "app" / "BoopKit" / "Voice" / "Takes.swift"

RATE = 11025        # the takes' sample rate on the board (VOICE.md §3)
TEXTURE = "robot-soft"
TRIM_DB = 45        # near-silence: 10 ms frames quieter than this, in dBFS
PAD_BEFORE_MS = 30  # kept before the first sound and after the last, so
PAD_AFTER_MS = 80   # breaths and decays aren't clipped
DRIVE = 2.2         # soft saturation before normalising: louder on a tiny speaker
PEAK = 0.92
MOUTH_MS = 20       # the mouth's resolution
MOUTH_OPEN = 0.2    # open while a frame is this loud, of the take's loudest frame

MOODS = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad",
         "calm", "engaged", "annoyed", "irritated", "whiny", "wounded"]
# Takes recorded in a mood Boop doesn't have, by the bank's label or, for
# the two with none, by id: the mood they're used in.
MOOD_OF = {"relieved": "happy", "weary": "whiny", "amused": "happy",
           "previous.go": "calm", "previous.oi": "curious"}
# The finish a take needs, from the fact the bank says it requires: a
# success word only on a success, a swear only on a failure.
FINISH_OF = {"success_confirmed": "success", "failure_confirmed": "failure"}


def kind(entry: dict) -> str:
    if entry["explicit"]:
        return "swear"
    return {"word": "word", "phrase": "phrase", "nonverbal": "sound"}[entry["category"]]


def mood(rec: dict) -> str:
    m = MOOD_OF.get(rec["id"]) or MOOD_OF.get(rec["mood"]) or rec["mood"]
    if m not in MOODS:
        raise SystemExit(f"voicegen: {rec['id']} is in mood {rec['mood']!r}, which isn't one of Boop's; add it to MOOD_OF")
    return m


def text(entry: dict) -> str:
    """The bubble's text: the bank's, in the board font's ASCII."""
    t = entry["text"].replace("....", "...")
    return t[:-1] if t.endswith(".") and not t.endswith("...") else t


def load(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path)) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1, path
        rate = w.getframerate()
        a = array("h", w.readframes(w.getnframes()))
    return [v / 32768 for v in a], rate


def rms(x: list[float]) -> float:
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0


def trim(x: list[float], rate: int) -> list[float]:
    step, floor = rate // 100, 10 ** (-TRIM_DB / 20)
    loud = [i for i in range(0, len(x), step) if rms(x[i:i + step]) > floor]
    if not loud:
        return x
    return x[max(0, loud[0] - rate * PAD_BEFORE_MS // 1000):min(len(x), loud[-1] + step + rate * PAD_AFTER_MS // 1000)]


def decimate(x: list[float], k: int) -> list[float]:
    """Every k-th sample after a box low-pass over k."""
    return [sum(x[max(0, i - k + 1):i + 1]) / min(k, i + 1) for i in range(0, len(x), k)]


def shape(x: list[float]) -> list[float]:
    """Saturate, normalise and fade the ends, as the old syllables were."""
    p = max(map(abs, x)) or 1
    y = [math.tanh(DRIVE * v / p) for v in x]
    p = max(map(abs, y)) or 1
    y = [PEAK * v / p for v in y]
    fin, fout = RATE * 3 // 1000, RATE * 12 // 1000
    for i in range(min(fin, len(y))):
        y[i] *= i / fin
    for i in range(min(fout, len(y))):
        y[-1 - i] *= i / fout
    return y


def to_u8(y: list[float]) -> bytes:
    return bytes(max(0, min(255, 128 + round(127 * v))) for v in y)


def mouth(y: list[float]) -> bytes:
    """1 for each MOUTH_MS the take is loud, else 0."""
    n = RATE * MOUTH_MS // 1000
    frames = [rms(y[i:i + n]) for i in range(0, len(y), n)]
    top = max(frames) or 1
    return bytes(1 if f >= MOUTH_OPEN * top else 0 for f in frames)


def convert(rec: dict) -> tuple[bytes, bytes]:
    x, rate = load(BANK / rec["files"][TEXTURE]["path"])
    if rate % RATE:
        raise SystemExit(f"voicegen: {rec['id']} is {rate} Hz, not a multiple of {RATE}")
    y = shape(decimate(trim(x, rate), rate // RATE))
    return to_u8(y), mouth(y)


def c_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_header(takes: list[dict], clips: list[bytes], mouths: list[bytes]) -> str:
    blob = b"".join(clips)
    digest = hashlib.sha256(blob + b"".join(mouths) + "".join(t["id"] + t["text"] for t in takes).encode()).hexdigest()[:12]
    lines = [
        "// Boop's voice: recorded takes as 8-bit unsigned samples at 11.025 kHz (plan/VOICE.md §3).",
        "// Generated by internal/tools/voicegen/voicegen.py from internal/boop-design/assets/boop-voice-v1/.",
        "// Don't edit; rerun the tool. Include from one .cpp only (voice/player.cpp).",
        "#pragma once",
        "#include <cstdint>",
        "",
        "namespace voice_assets {",
        "",
        f"constexpr uint32_t kRate = {RATE};",
        f'constexpr const char* kVersion = "{digest}";',
        f"constexpr int kTakes = {len(takes)};",
        f"constexpr uint32_t kBytes = {len(blob)};",
        f"constexpr uint32_t kMouthMs = {MOUTH_MS};",
        "",
        "struct Take {",
        "  const char* id;",
        "  const char* text;  // the bubble's",
        "  uint32_t at;       // offset into kSamples",
        "  uint16_t len;      // samples",
        "  uint16_t mouth;    // offset into kMouth: one entry per kMouthMs (kRate * kMouthMs / 1000 samples), rounded up",
        "};",
        "",
        "static const Take kTake[] = {",
    ]
    at = m = 0
    for t, c, mo in zip(takes, clips, mouths):
        lines.append(f"    {{{c_str(t['id'])}, {c_str(t['text'])}, {at}, {len(c)}, {m}}},")
        at += len(c)
        m += len(mo)
    lines += ["};", "", "static const uint8_t kMouth[] = {"]
    allm = b"".join(mouths)
    for i in range(0, len(allm), 64):
        lines.append("    " + ",".join(str(b) for b in allm[i:i + 64]) + ",")
    lines += ["};", "", "static const uint8_t kSamples[] = {"]
    for i in range(0, len(blob), 32):
        lines.append("    " + ",".join(str(b) for b in blob[i:i + 32]) + ",")
    lines += ["};", "", "}  // namespace voice_assets", ""]
    return "\n".join(lines)


def write_swift(takes: list[dict]) -> str:
    lines = [
        "// Boop's voice: the recorded takes on the board (plan/VOICE.md §3).",
        "// Generated by internal/tools/voicegen/voicegen.py from internal/boop-design/assets/boop-voice-v1/.",
        "// Don't edit; rerun the tool.",
        "",
        "extension Take {",
        "    /// Every take the board has, in the bank's order.",
        "    public static let all: [Take] = [",
    ]
    for t in takes:
        finish = f'"{t["finish"]}"' if t["finish"] else "nil"
        lines.append(f'        Take(id: "{t["id"]}", text: {json.dumps(t["text"])}, meaning: "{t["meaning"]}", '
                     f'kind: .{t["kind"]}, mood: "{t["mood"]}", finish: {finish}, ms: {t["ms"]}),')
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=OUT, help="the header to write (default: firmware/assets/voice.h)")
    ap.add_argument("--swift", type=Path, default=SWIFT, help="the Mac's table (default: app/BoopKit/Voice/Takes.swift)")
    ap.add_argument("--wav-dir", type=Path, help="also write every converted take as a WAV here")
    args = ap.parse_args()

    manifest = json.loads((BANK / "manifest.json").read_text())
    entries = {e["id"]: e for e in json.loads((BANK / "dictionary.json").read_text())["entries"]}
    takes, clips, mouths = [], [], []
    for rec in manifest["recordings"]:
        e = entries[rec["entryId"]]
        clip, mo = convert(rec)
        takes.append({"id": rec["id"], "text": text(e), "meaning": e["intent"], "kind": kind(e), "mood": mood(rec),
                      "finish": FINISH_OF.get(e["requires"]), "ms": len(clip) * 1000 // RATE})
        clips.append(clip)
        mouths.append(mo)
    args.out.write_text(write_header(takes, clips, mouths))
    args.swift.write_text(write_swift(takes))
    if args.wav_dir:
        args.wav_dir.mkdir(parents=True, exist_ok=True)
        for t, c in zip(takes, clips):
            with wave.open(str(args.wav_dir / f"{t['id']}.wav"), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(1)
                w.setframerate(RATE)
                w.writeframes(c)
    ms = [t["ms"] for t in takes]
    print(f"voicegen: {len(takes)} takes, {sum(map(len, clips))} B of samples, {sum(map(len, mouths))} B of mouth "
          f"({min(ms)}–{max(ms)} ms) → {args.out.relative_to(REPO)}, {args.swift.relative_to(REPO)}")


if __name__ == "__main__":
    main()
