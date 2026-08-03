#!/usr/bin/env python3
"""Render Boop's chirps to the app's bundled .caf sounds.

Square-wave chiptune, deliberately crude — it should read as "creature," not
"notification." Run with no arguments to regenerate the shipped assets; pass
--out to render a candidate somewhere else and audition it with afplay first.
"""
import argparse
import math
import shutil
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SAMPLE_RATE = 44100
PEAK = int(32767 * 0.20)
ROOT = Path(__file__).resolve().parents[1]
SOUNDS_DIR = ROOT / "Boop" / "Resources" / "Sounds"


def square_sample(frequency, t):
    return 1.0 if math.sin(2.0 * math.pi * frequency * t) >= 0 else -1.0


def envelope(index, total):
    attack = max(1, int(SAMPLE_RATE * 0.006))
    release = max(1, int(SAMPLE_RATE * 0.028))
    if index < attack:
        return index / attack
    remaining = total - index
    if remaining < release:
        return max(0.0, remaining / release)
    return 1.0


def render_notes(notes):
    samples = []
    for frequency, duration, gap in notes:
        count = int(SAMPLE_RATE * duration)
        for i in range(count):
            t = i / SAMPLE_RATE
            value = square_sample(frequency, t) * envelope(i, count)
            samples.append(int(PEAK * value))
        samples.extend([0] * int(SAMPLE_RATE * gap))
    return samples


def write_wav(path, samples):
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))


def convert_to_caf(wav_path, caf_path):
    subprocess.run(
        ["afconvert", "-f", "caff", "-d", "LEI16", str(wav_path), str(caf_path)],
        check=True,
    )


# One motif per event, and each has to be tellable from the others across a
# room (PRODUCT.md §10.3). Kept in step with playStateChirp in
# firmware/esp32/firmware/main.cpp so the desktop and the device speak the
# same language — the Pebble has no buzzer yet, so today only the Mac is
# audible, but the grammar carries over unchanged when one lands.
CHIRPS = {
    # Rising two-note "meep?" — a question, because it wants an answer.
    "attention": [(880.0, 0.09, 0.015), (1245.0, 0.09, 0.0)],
    # One bright blip. Finishing is a full stop, not a fanfare; a trill here
    # got tiring at the rate an agent actually completes work.
    "celebrate": [(1318.51, 0.11, 0.0)],
    "error": [(330.0, 0.18, 0.0)],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=SOUNDS_DIR,
        help="directory to write the .caf files into (default: the app's Sounds resources). "
        "Point it at /tmp to audition a candidate without dirtying the tree.",
    )
    args = parser.parse_args()

    if shutil.which("afconvert") is None:
        raise SystemExit("afconvert is required to generate CAF chirps on macOS")

    args.out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        for name, notes in CHIRPS.items():
            wav_path = tmp_dir / f"{name}.wav"
            caf_path = args.out / f"{name}.caf"
            write_wav(wav_path, render_notes(notes))
            convert_to_caf(wav_path, caf_path)
            print(caf_path)


if __name__ == "__main__":
    main()
