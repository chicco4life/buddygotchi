#!/usr/bin/env python3
"""Press a buddy button over USB serial and verify the device's response.

Sends the firmware's debug "btn" command, which injects a synthetic A/B
press through the SAME approval path as the physical buttons, then prints
what the device emits back. With --mock, first arms a fake approval prompt
(firmware "mockprompt" command) so the press has something to act on even
with no daemon connected — handy for self-verifying button input during
development. Pure stdlib — no pyserial.

Usage:
  python3 tools/button.py a               # press A (approve)
  python3 tools/button.py b               # press B (deny)
  python3 tools/button.py --mock a        # arm a fake prompt, then press A
  python3 tools/button.py --port /dev/cu.usbserial-XXX b

Exit status is 0 only when the device confirms the press: a "<<BTN ...>>"
breadcrumb, plus the permission JSON ("decision":"allow"/"deny") whenever a
prompt was armed.

Prereq: firmware must include the handleSerialCommand "btn"/"mockprompt"
handlers (see main.cpp).
"""

import argparse, glob, os, sys, termios, time


def find_port() -> str:
    for pat in ('/dev/cu.usbserial-*', '/dev/cu.wchusbserial*', '/dev/cu.usbmodem*'):
        m = sorted(glob.glob(pat))
        if m: return m[0]
    sys.exit('no ESP32 serial port found (looked for cu.usbserial-*, cu.wchusbserial*, cu.usbmodem*)')


def open_serial(port: str) -> int:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = termios.IGNBRK                                       # iflag
    attrs[1] = 0                                                    # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL         # cflag: 8N1
    attrs[3] = 0                                                    # lflag: no canonical, no echo
    attrs[4] = termios.B115200                                      # ispeed
    attrs[5] = termios.B115200                                      # ospeed
    cc = list(attrs[6])
    cc[termios.VMIN]  = 0
    cc[termios.VTIME] = 0
    attrs[6] = cc
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def read_some(fd: int) -> bytes:
    try:
        return os.read(fd, 8192)
    except BlockingIOError:
        return b''


def drain(fd: int, secs: float) -> str:
    """Collect everything the device emits for `secs`, as text."""
    buf = bytearray()
    end = time.monotonic() + secs
    while time.monotonic() < end:
        chunk = read_some(fd)
        if chunk: buf.extend(chunk)
        else:     time.sleep(0.02)
    return buf.decode('utf-8', errors='replace')


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('button', choices=['a', 'b', 'A', 'B'], help='which button to press (a=approve, b=deny)')
    ap.add_argument('--mock', action='store_true', help='arm a fake approval prompt before pressing')
    ap.add_argument('--port', default=None, help='serial port (default: first cu.usbserial-*)')
    ap.add_argument('--settle', type=float, default=2.0, help='seconds to drain log noise before sending')
    ap.add_argument('--wait',   type=float, default=1.5, help='seconds to read the response after pressing')
    args = ap.parse_args()
    which = args.button.lower()

    port = args.port or find_port()
    print(f'button: port={port} press={which} mock={args.mock}', file=sys.stderr)

    fd = open_serial(port)
    try:
        drain(fd, args.settle)  # discard pre-existing log noise

        if args.mock:
            os.write(fd, b'mockprompt\n')
            ack = drain(fd, 1.0)
            if '<<BTN mockprompt armed>>' not in ack:
                print('WARNING: no mockprompt ack from device. Got:\n' + ack.strip(), file=sys.stderr)

        os.write(fd, f'btn {which}\n'.encode())
        resp = drain(fd, args.wait)
    finally:
        os.close(fd)

    # Surface only the meaningful lines; framework debug logs are noise.
    lines = [ln for ln in resp.splitlines()
             if '<<BTN' in ln or '"cmd":"permission"' in ln]
    for ln in lines:
        print('  ' + ln.strip())

    breadcrumb = f'<<BTN {which}' in resp
    armed = args.mock or 'sent>>' in resp
    decision = 'allow' if which == 'a' else 'deny'
    approval_ok = (f'"decision":"{decision}"' in resp) if armed else True

    if not breadcrumb:
        sys.exit(f'FAIL: no "<<BTN {which} ...>>" breadcrumb — is the new firmware flashed?')
    if armed and not approval_ok:
        sys.exit(f'FAIL: expected permission JSON with "decision":"{decision}" but did not see it')
    if 'noop' in resp:
        print(f'OK: press registered, but no prompt was armed (use --mock to test approval).')
    else:
        print(f'OK: button {which.upper()} pressed -> "{decision}" sent and confirmed.')


if __name__ == '__main__':
    main()
