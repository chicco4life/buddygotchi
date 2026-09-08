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
    """Read 8-bit RGB/RGBA PNGs without a required imaging dependency."""
    raw = path.read_bytes()
    if raw[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path}: not a PNG')
    pos, packed = 8, bytearray()
    while pos < len(raw):
        size = struct.unpack('>I', raw[pos:pos+4])[0]
        kind, data = raw[pos+4:pos+8], raw[pos+8:pos+8+size]
        if kind == b'IHDR':
            w, h, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', data)
            if depth != 8 or color not in (2, 6) or interlace or compression or filtering:
                raise ValueError(f'{path}: requires non-interlaced 8-bit RGB/RGBA PNG')
        elif kind == b'IDAT':
            packed.extend(data)
        pos += size + 12
    bpp = 3 if color == 2 else 4
    stride = w * bpp
    pixels = zlib.decompress(packed)
    if len(pixels) != (stride + 1) * h:
        raise ValueError(f'{path}: invalid pixel data length')
    previous = bytearray(stride)
    rgb = bytearray()
    for y in range(h):
        start = y * (stride + 1)
        mode = pixels[start]
        row = bytearray(pixels[start+1:start+1+stride])
        for x in range(stride):
            a, b, c = row[x-bpp] if x >= bpp else 0, previous[x], previous[x-bpp] if x >= bpp else 0
            if mode == 0: predictor = 0
            elif mode == 1: predictor = a
            elif mode == 2: predictor = b
            elif mode == 3: predictor = (a+b)//2
            elif mode == 4:
                p = a+b-c
                distances = (abs(p-a), abs(p-b), abs(p-c))
                predictor = (a, b, c)[distances.index(min(distances))]
            else: raise ValueError(f'{path}: invalid PNG filter {mode}')
            row[x] = (row[x] + predictor) & 255
        for x in range(0, stride, bpp):
            rgb.extend(row[x:x+3])
        previous = row
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
