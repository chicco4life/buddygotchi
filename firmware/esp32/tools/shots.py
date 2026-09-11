#!/usr/bin/env python3
"""Contact sheet: every RenderState v2 cell rendered on the real device.

One held-open serial session per cell: send the frame, wait for the state,
run the cell recipe, freeze at its exact state-relative offset,
screenshot, unfreeze. Cells come from shot_cells.py, shared with golden.py.
"""
import argparse, json, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import buddyctl  # noqa: E402
from shot_cells import cells, prepare, trigger  # noqa: E402

OUT = Path('/tmp/boop-shots')


def require_exclusive(s) -> None:
    """Refuse to drive the device while the Boop app is connected over BLE.

    Two writers on one screen silently corrupts every capture: the app's own
    frames (real cards, session dots) land between ours and the screenshot.
    That produced a set of contaminated goldens before this guard existed.
    """
    if s.framed_json("ping", "PONG", 3).get("usbOnly") is True:
        return  # USB frames also set dataConnected; this build has no BLE writer.
    if s.framed_json("state", "STATE", 3).get("connected"):
        raise SystemExit(
            "The Boop app is connected to this buddy over Bluetooth and is pushing its own\n"
            "frames. Quit Boop (menu bar, Quit) and run this again; captures taken now are\n"
            "not reproducible."
        )


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", choices=list(cells()))
    args, extra = ap.parse_known_args()
    port = buddyctl.find_port()
    with buddyctl.SerialBuddy(port, timeout=5) as guard:
        require_exclusive(guard)
    selected = {n: f for n, f in cells().items() if not args.only or n == args.only}
    with buddyctl.SerialBuddy(port, timeout=5) as s:
        s.write_line('clock clear'); s.write_line('imu set 0 0 0.98'); time.sleep(0.3)
        # Cosmetics persist in NVS across frames; start every sheet from the bare buddy.
        s.write_line(json.dumps({'v': 2, 'state': 'idle', 'cosmetic': {'skin': '', 'accessory': '', 'silhouette': ''}})); time.sleep(0.5)
    for name, cell in selected.items():
        frame = cell.copy()
        settle = frame.pop("settle")
        command = frame.pop("trigger", None)
        frame = {**{k: v for k, v in frame.items() if k != 't'}, 't': int(time.time() * 1000)}
        with buddyctl.SerialBuddy(port, timeout=5) as s:
            prepare(s)
            # A bridge state that differs from the cell's, so the cell frame is a
            # state change and `stateAt` (the anchor for every phase, including
            # the working gaze hop) is fresh regardless of host timing.
            bridge = 'idle' if frame['state'] != 'idle' else 'working'
            s.write_line(json.dumps({'v': 2, 'state': bridge})); time.sleep(0.4)
            if "notice" in frame:
                frame["notice"]["id"] = int(time.monotonic()*1000) % 2000000000 + 1
            s.write_line(json.dumps(frame, ensure_ascii=False, separators=(',', ':')))
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and s.framed_json('state', 'STATE', 3).get('creature') != frame['state']:
                time.sleep(0.2)
            trigger(s, command)
            time.sleep(settle / 1000.0)
            s.write_line(f'clock settle {settle}'); time.sleep(0.15)   # exact offset from state entry
        subprocess.run([sys.executable, str(HERE / 'buddyctl.py'), 'screenshot', '--scale', '1',
                        '--out', str(OUT / f'{name}.png'), *extra], check=True, capture_output=True)
        with buddyctl.SerialBuddy(port, timeout=5) as s:
            s.write_line('clock clear')
    with buddyctl.SerialBuddy(port, timeout=5) as s:
        s.write_line('imu clear')
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print(f'{len(selected)} cells in {OUT} (install Pillow for a single grid image)')
        return 0
    images = [(n, Image.open(OUT / f'{n}.png').convert('RGB')) for n in selected]
    w = max(i.width for _, i in images) + 16; h = max(i.height for _, i in images) + 36
    cols = 4; rows = (len(images) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * h), (24, 24, 24)); draw = ImageDraw.Draw(sheet)
    for k, (n, img) in enumerate(images):
        x, y = (k % cols) * w + 8, (k // cols) * h + 28
        sheet.paste(img, (x, y)); draw.text((x, y - 20), n, fill=(230, 230, 230))
    sheet.save(OUT / 'contact-sheet.png'); print(OUT / 'contact-sheet.png')
    return 0


if __name__ == '__main__':
    sys.exit(main())
