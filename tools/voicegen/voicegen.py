"""Builds Boop's voice assets (plan/VOICE.md §8, plan/PLAN.md F5) as C arrays.

Every syllable and real word is synthesised offline with macOS `say`,
converted with `afconvert`, then trimmed, pitched up, squeezed and
normalised into 8-bit unsigned samples at 11.025 kHz. The output,
firmware/assets/voice.h, is checked in; rerun this only to change the voice:

    tools/.venv/bin/python tools/voicegen/voicegen.py [--wav-dir DIR]

The syllable set and the vocabulary come from
app/BoopKit/Voice/Sounds.swift, the single source, in its order: the
firmware finds a clip by its index in those lists.

Syllables use an Italian voice, so vowels come out pure and open (VOICE.md
§3); a few are respelled so Italian reads them the way Voice means them
(`ki` → `chi`, `ge` → `ghe`, `ya` → `ia`). The real words use an English
voice. The two hums can't be spoken (Italian spells out `mm`), so they're
synthesised as a nasal tone.

`--wav-dir` also writes every processed clip as a WAV, for listening.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import math
import re
import subprocess
import tempfile
import wave
from array import array
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOUNDS = REPO / "app" / "BoopKit" / "Voice" / "Sounds.swift"
OUT = REPO / "firmware" / "assets" / "voice.h"

RATE = 11025          # the clips' sample rate (VOICE.md §8)
SAY_RATE = 22050      # what afconvert hands us
SYL_VOICE, SYL_WPM = "Alice", 230
WORD_VOICE, WORD_WPM = "Samantha", 210
SYL_PITCH = 1.30      # pitched up: small and chiptune
WORD_PITCH = 1.15     # less, so the one real word stays clear
SYL_MAX = 1800        # samples: about 2 KB and 163 ms per syllable
WORD_MAX = 5600       # about 6 KB and 508 ms per word
DRIVE = 2.2           # soft saturation before normalising: louder on a tiny speaker

# Italian spellings for syllables Italian would read differently.
RESPELL = {
    "ka": "ca", "ke": "che", "ki": "chi", "ko": "co", "ku": "cu",
    "ge": "ghe", "gi": "ghi",
    "ya": "ia", "yo": "io", "yu": "iu", "wa": "ua", "we": "ue", "wo": "uo",
    "kun": "cun",
}


def swift_list(src: str, name: str) -> list[str]:
    m = re.search(rf"static let {name}(?:: \[String\])? =\s*\[(.*?)\]", src, re.S)
    if not m:
        raise SystemExit(f"voicegen: can't find `{name}` in {SOUNDS}")
    return re.findall(r'"([^"]*)"', m.group(1))


def load_sets() -> tuple[list[str], list[str]]:
    """Sounds.all and Sounds.vocabulary, rebuilt the way Sounds.swift does."""
    src = SOUNDS.read_text()
    cons, vows = swift_list(src, "consonants"), swift_list(src, "vowels")
    m = re.search(r"static let all: \[String\] =(.*?)public static let hums", src, re.S)
    if not m:
        raise SystemExit("voicegen: Sounds.all changed shape; update load_sets")
    # consonants × vowels, then `+ [...]`, `+ vowels` and `+ hums` in order.
    order: list[str] = [c + v for c in cons for v in vows]
    for part in re.split(r"\n\s*\+", m.group(1))[1:]:
        part = part.strip()
        if part.startswith("["):
            order += re.findall(r'"([^"]*)"', part)
        elif part == "vowels":
            order += vows
        elif part == "hums":
            order += swift_list(src, "hums")
        else:
            raise SystemExit(f"voicegen: don't know `{part}` in Sounds.all")
    vocab = swift_list(src, "vocabulary")
    if len(order) != 64 or len(set(order)) != 64:
        raise SystemExit(f"voicegen: expected 64 distinct syllables, got {len(order)}")
    return order, vocab


def speak(text: str, voice: str, wpm: int, tmp: Path) -> list[float]:
    aiff, wav = tmp / f"{abs(hash((text, voice)))}.aiff", tmp / f"{abs(hash((text, voice)))}.wav"
    subprocess.run(["say", "-v", voice, "-r", str(wpm), "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SAY_RATE}", "-c", "1", str(aiff), str(wav)],
                   check=True)
    with wave.open(str(wav)) as w:
        assert w.getframerate() == SAY_RATE and w.getsampwidth() == 2
        a = array("h", w.readframes(w.getnframes()))
    return [x / 32768 for x in a]


def trim(x: list[float], rate: int) -> list[float]:
    """Cut the silence around the sound, keeping 5 ms either side."""
    win = rate // 200
    peak = max((abs(v) for v in x), default=0) or 1
    loud = [i for i in range(0, len(x), win) if max(abs(v) for v in x[i:i + win]) > 0.04 * peak]
    if not loud:
        return x
    a, b = max(0, loud[0] - win), min(len(x), loud[-1] + 2 * win)
    return x[a:b]


def pitch_down_rate(x: list[float], pitch: float) -> list[float]:
    """Resample to RATE while raising pitch and tempo by `pitch`: a box
    low-pass over one output step, then linear interpolation."""
    step = SAY_RATE * pitch / RATE
    k = max(1, round(step))
    pre = [sum(x[max(0, i - k + 1):i + 1]) / min(k, i + 1) for i in range(len(x))]
    out, pos = [], 0.0
    while pos < len(pre) - 1:
        i = int(pos)
        f = pos - i
        out.append(pre[i] * (1 - f) + pre[i + 1] * f)
        pos += step
    return out


def shape(x: list[float], cap: int) -> list[float]:
    """Saturate, normalise, cap the length and fade the ends."""
    if len(x) > cap:
        x = x[:cap]
    y = [math.tanh(DRIVE * v) for v in x]
    peak = max((abs(v) for v in y), default=0) or 1
    y = [0.92 * v / peak for v in y]
    fin, fout = RATE * 3 // 1000, RATE * 12 // 1000
    for i in range(min(fin, len(y))):
        y[i] *= i / fin
    for i in range(min(fout, len(y))):
        y[-1 - i] *= i / fout
    return y


def hum(k: str) -> list[float]:
    """A hummed syllable: a nasal tone with a soft start and a falling end."""
    f0, bright = (240.0, 0.5) if k == "mm" else (275.0, 0.8)
    n = RATE * 150 // 1000
    out, ph = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (1 + 0.02 * math.sin(2 * math.pi * 6 * t)) * (1 - 0.06 * i / n)
        ph += 2 * math.pi * f / RATE
        v = sum(bright ** (h - 1) / h * math.sin(h * ph) for h in range(1, 7))
        env = min(1.0, i / (RATE * 0.015)) * min(1.0, (n - i) / (RATE * 0.05))
        out.append(v * env)
    return out


def to_u8(y: list[float]) -> bytes:
    return bytes(max(0, min(255, 128 + round(127 * v))) for v in y)


def build(name: str, kind: str, tmp: Path) -> bytes:
    if kind == "hum":
        return to_u8(shape(hum(name), SYL_MAX))
    if kind == "syl":
        raw = speak(RESPELL.get(name, name), SYL_VOICE, SYL_WPM, tmp)
        return to_u8(shape(pitch_down_rate(trim(raw, SAY_RATE), SYL_PITCH), SYL_MAX))
    raw = speak(name, WORD_VOICE, WORD_WPM, tmp)
    return to_u8(shape(pitch_down_rate(trim(raw, SAY_RATE), WORD_PITCH), WORD_MAX))


def c_table(name: str, names: list[str], clips: list[bytes], offset: int) -> list[str]:
    rows = [f"static const Clip {name}[] = {{"]
    for n, c in zip(names, clips):
        rows.append(f'    {{"{n}", {offset}, {len(c)}}},')
        offset += len(c)
    rows.append("};")
    return rows


def write_header(syl: list[str], sclips: list[bytes], words: list[str], wclips: list[bytes]) -> str:
    blob = b"".join(sclips + wclips)
    digest = hashlib.sha256(blob).hexdigest()[:12]
    lines = [
        "// Boop's voice: 8-bit unsigned samples at 11.025 kHz (plan/VOICE.md §8).",
        "// Generated by tools/voicegen/voicegen.py from app/BoopKit/Voice/Sounds.swift.",
        "// Don't edit; rerun the tool. Include from one .cpp only (voice/player.cpp).",
        "#pragma once",
        "#include <cstdint>",
        "",
        "namespace voice_assets {",
        "",
        f"constexpr uint32_t kRate = {RATE};",
        f'constexpr const char* kVersion = "{digest}";',
        f"constexpr int kSyllables = {len(syl)};",
        f"constexpr int kWords = {len(words)};",
        f"constexpr uint32_t kBytes = {len(blob)};",
        "",
        "struct Clip {",
        "  const char* name;",
        "  uint32_t at;   // offset into kSamples",
        "  uint16_t len;  // samples",
        "};",
        "",
    ]
    lines += c_table("kSyllable", syl, sclips, 0)
    lines.append("")
    lines += c_table("kWord", words, wclips, sum(len(c) for c in sclips))
    lines += ["", "static const uint8_t kSamples[] = {"]
    for i in range(0, len(blob), 32):
        lines.append("    " + ",".join(str(b) for b in blob[i:i + 32]) + ",")
    lines += ["};", "", "}  // namespace voice_assets", ""]
    return "\n".join(lines)


def write_wav(path: Path, data: bytes) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(data)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--wav-dir", type=Path, help="also write every clip as a WAV here")
    args = ap.parse_args()

    syl, words = load_sets()
    jobs = [(s, "hum" if s in ("mm", "nn") else "syl") for s in syl] + [(w, "word") for w in words]
    with tempfile.TemporaryDirectory() as d, cf.ThreadPoolExecutor(8) as pool:
        clips = list(pool.map(lambda j: build(j[0], j[1], Path(d)), jobs))
    sclips, wclips = clips[:len(syl)], clips[len(syl):]
    args.out.write_text(write_header(syl, sclips, words, wclips))
    if args.wav_dir:
        args.wav_dir.mkdir(parents=True, exist_ok=True)
        for (n, _), c in zip(jobs, clips):
            write_wav(args.wav_dir / f"{n}.wav", c)

    def ms(c: bytes) -> int:
        return len(c) * 1000 // RATE

    print(f"voicegen: {len(syl)} syllables, {sum(map(len, sclips))} B "
          f"({min(map(ms, sclips))}–{max(map(ms, sclips))} ms); {len(words)} words, "
          f"{sum(map(len, wclips))} B ({min(map(ms, wclips))}–{max(map(ms, wclips))} ms) → {args.out}")
    capped = [n for (n, k), c in zip(jobs, clips) if len(c) >= (WORD_MAX if k == "word" else SYL_MAX)]
    if capped:
        print("voicegen: cut to the cap: " + " ".join(capped))


if __name__ == "__main__":
    main()
