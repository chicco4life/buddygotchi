#!/usr/bin/env python3
"""Record/check shots.sh captures; normalized RGB mean absolute error (0–1)."""
import argparse
from pathlib import Path
import shutil
import struct
import zlib

from shot_cells import cells
from buddyctl import write_png


def read_png(path):
    """Read the PNGs `buddyctl.write_png` produces: 8-bit RGB, filter 0, no interlace."""
    raw = path.read_bytes()
    if raw[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path}: not a PNG')
    pos, packed, w, h = 8, bytearray(), 0, 0
    while pos < len(raw):
        size = struct.unpack('>I', raw[pos:pos+4])[0]
        kind, data = raw[pos+4:pos+8], raw[pos+8:pos+8+size]
        if kind == b'IHDR':
            w, h, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', data)
            if (depth, color, compression, filtering, interlace) != (8, 2, 0, 0, 0):
                raise ValueError(f'{path}: expected an 8-bit RGB filter-0 PNG as written by buddyctl')
        elif kind == b'IDAT':
            packed.extend(data)
        pos += size + 12
    stride = w * 3
    pixels = zlib.decompress(packed)
    if len(pixels) != (stride + 1) * h:
        raise ValueError(f'{path}: invalid pixel data length')
    rgb = bytearray()
    for y in range(h):
        start = y * (stride + 1)
        if pixels[start] != 0:
            raise ValueError(f'{path}: unexpected PNG filter {pixels[start]}')
        rgb.extend(pixels[start+1:start+1+stride])
    return w, h, rgb


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=['record', 'check'])
    ap.add_argument('--dir', type=Path, default=Path('tests/golden/ws-amoled164'))
    ap.add_argument('--shots', type=Path, default=Path('/tmp/boop-shots'))
    ap.add_argument('--threshold', type=float, default=0.02)
    args = ap.parse_args()
    if not 0 <= args.threshold <= 1:
        ap.error('--threshold must be between 0 and 1')
    names = list(cells())
    missing = [args.shots / f'{n}.png' for n in names if not (args.shots / f'{n}.png').is_file()]
    if missing:
        print('Missing captures; run tools/shots.sh first: ' + ', '.join(map(str, missing)))
        return 1
    if args.action == 'record':
        args.dir.mkdir(parents=True, exist_ok=True)
        for name in names:
            read_png(args.shots / f'{name}.png')
            shutil.copyfile(args.shots / f'{name}.png', args.dir / f'{name}.png')
        print(f'Recorded {len(names)} goldens in {args.dir}')
        return 0
    failed = 0
    for name in names:
        actual, reference = args.shots / f'{name}.png', args.dir / f'{name}.png'
        diff_path = args.shots / f'{name}.diff.png'
        diff_path.unlink(missing_ok=True)
        try:
            w, h, a = read_png(actual)
            rw, rh, b = read_png(reference)
            if (w, h) != (rw, rh):
                write_png(diff_path, w, h, bytes([255, 0, 255]) * w * h)
                raise ValueError(f'size mismatch {(w,h)} != {(rw,rh)}')
            diff = bytes(abs(x-y) for x, y in zip(a, b))
            error = sum(diff) / (len(diff) * 255)
            print(f'{name}: {error:.6f} (threshold {args.threshold})')
            if error > args.threshold:
                write_png(diff_path, w, h, diff)
                failed += 1
        except (OSError, ValueError, zlib.error) as exc:
            print(f'{name}: FAIL: {exc}')
            failed += 1
    print(f'{len(names)-failed}/{len(names)} passed')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
