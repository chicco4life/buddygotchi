#!/usr/bin/env python3
"""Reserve the ESP32 for setup, a scenario, and restoration on normal failure or interruption."""
import argparse
from contextlib import contextmanager, nullcontext
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'firmware/esp32/tools'))
from device_lease import reserve


def gui_running():
    listing = subprocess.check_output(['ps', '-axo', 'comm=,args='], text=True)
    return any(Path(line.split()[0]).name == 'Boop' and '--headless' not in line for line in listing.splitlines() if line.split())


@contextmanager
def gui_claim():
    # Same guard as the GUI: keep it from reconnecting during a reservation.
    with open(f'/tmp/boop-instance-{os.getuid()}.lock', 'a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('Quit the Boop GUI to release BLE before hardware testing.')
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def verify_usb_only():
    from buddyctl import SerialBuddy
    with SerialBuddy(timeout=5) as serial:
        info = serial.framed_json('ping', 'PONG', 5)
    if info.get('board') != 'ws-amoled164' or info.get('usbOnly') is not True:
        raise RuntimeError('USB-only verification requires ws-amoled164-usb-debug firmware (usbOnly=true).')
    return info


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--usb-only', action='store_true', help='Allow the GUI to stay open; require USB-only debug firmware before the scenario')
    ap.add_argument('--setup', help='Executable script: flash candidate and verify board/firmware identity')
    ap.add_argument('--restore', help='Executable script: restore and verify the known-good firmware')
    ap.add_argument('--evidence', required=True, type=Path)
    ap.add_argument('command', nargs=argparse.REMAINDER)
    args = ap.parse_args()
    if args.setup and not args.restore:
        ap.error('--setup requires --restore')
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        ap.error('provide a scenario command after --')
    for script in (args.setup, args.restore):
        if script and not os.access(Path(script).resolve(), os.X_OK):
            ap.error(f'Script must exist and be executable: {script}')
    with reserve() as token, (nullcontext() if args.usb_only else gui_claim()):
        if not args.usb_only and gui_running():
            raise SystemExit('Quit the Boop GUI before hardware testing to release BLE. Headless instances can stay running. Relaunch the GUI yourself afterward.')
        args.evidence.mkdir(parents=True, exist_ok=False)
        env = dict(os.environ, BOOP_DEVICE_LEASE=token)
        result = {'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)), 'command': command, 'started': time.time()}
        def run(cmd, name):
            with (args.evidence / f'{name}.log').open('wb') as log:
                proc = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    return proc.wait()
                except BaseException:
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait()
                    raise
        def interrupted(signum, frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, interrupted)
        code = 1
        try:
            result['setup'] = run([str(Path(args.setup).resolve())], 'setup') if args.setup else 0
            if result['setup'] == 0:
                if args.usb_only:
                    result['usbOnly'] = verify_usb_only()
                code = result['scenario'] = run(command, 'scenario')
        except RuntimeError as exc:
            result['error'] = str(exc)
            print(str(exc), file=sys.stderr)
        except KeyboardInterrupt:
            result['interrupted'] = True
            code = 130
        finally:
            # A second interrupt must not abandon firmware restoration.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            if args.restore:
                result['restore'] = run([str(Path(args.restore).resolve())], 'restore')
                if result['restore']:
                    code = 1
                    print('RESTORATION FAILED: inspect restore.log before using the device.', file=sys.stderr)
            result['finished'] = time.time()
            (args.evidence / 'result.json').write_text(json.dumps(result, indent=2))
        print(f'Device run finished; evidence: {args.evidence}')
        return code


if __name__ == '__main__':
    raise SystemExit(main())
