#!/usr/bin/env bash
set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 - "$TOOLS_DIR" "$@" <<'PY'
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
sys.path.insert(0, str(root))
from shot_cells import cells
out = Path('/tmp/boop-shots')
out.mkdir(parents=True, exist_ok=True)
paths = []
import time
import buddyctl
port = buddyctl.find_port()
def serial(line, marker=None):
    with buddyctl.SerialBuddy(port, timeout=5) as s:
        s.write_line(line)
        return s.framed_json(line, marker, 3) if marker else time.sleep(0.15)
# Freeze AFTER the springs settle, at the device's own current time: freezing
# at t=0 before anything eases open leaves every eye shut and no card armed.
serial('clock clear'); serial('imu set 0 0 0.98')
for name, frame in cells().items():
    def run(*args):
        subprocess.run([sys.executable, str(root / 'buddyctl.py'), *args, *sys.argv[2:]], check=True)
    frame = {k: v for k, v in frame.items() if k != 't'}
    frame['t'] = int(time.time() * 1000)
    run('frame', '--json', json.dumps(frame, ensure_ascii=False))
    run('expect', '--state', frame['state'])
    time.sleep(0.6 if frame['state'] == 'done' else 2.5)   # cheers are short; let others settle
    serial(f"clock {serial('ping', 'PONG')['up']}")
    path = out / f'{name}.png'
    run('screenshot', '--scale', '1', '--out', str(path))
    serial('clock clear')
    paths.append(path)
serial('imu clear')
try:
    from PIL import Image, ImageDraw
except ImportError:
    if shutil.which('montage'):
        args = ['montage']
        for path in paths:
            args += ['-label', path.stem, str(path)]
        subprocess.run(args + ['-tile', '4x', '-geometry', '+8+8', str(out / 'contact-sheet.png')], check=True)
        print(out / 'contact-sheet.png')
    else:
        print(f'Pillow and ImageMagick montage unavailable; individual PNGs remain in {out}')
else:
    images = [Image.open(path).convert('RGB') for path in paths]
    w = max(i.width for i in images) + 16
    h = max(i.height for i in images) + 36
    grid = Image.new('RGB', (4 * w, math.ceil(len(images) / 4) * h), '#202020')
    draw = ImageDraw.Draw(grid)
    for index, (path, im) in enumerate(zip(paths, images)):
        x, y = index % 4 * w, index // 4 * h
        grid.paste(im, (x + 8, y + 28))
        draw.text((x + 8, y + 8), path.stem, fill='white')
    grid.save(out / 'contact-sheet.png')
    print(out / 'contact-sheet.png')
PY
