#!/usr/bin/env python3
"""Capture the M5StickC Plus 2 display via USB serial.

Triggers the firmware's "screenshot" command, decodes the framed
RGB565-LE response, and writes a PNG. Pure stdlib — no pyserial, no
Pillow.

Usage:
  python3 tools/screenshot.py                 # auto-detect port, write screenshot.png
  python3 tools/screenshot.py --out foo.png
  python3 tools/screenshot.py --port /dev/cu.usbserial-XXX

Prereq: firmware must include the dumpScreenshot() handler. Reads run
in the panel's CURRENT rotation; landscape clock mode → 240x135 PNG.
"""

import argparse, base64, glob, os, re, struct, sys, termios, time, zlib


SCR_BEGIN = b'<<SCR_BEGIN '
SCR_END   = b'<<SCR_END>>'


def find_port() -> str:
    for pat in ('/dev/cu.usbserial-*', '/dev/cu.wchusbserial*', '/dev/cu.usbmodem*'):
        m = sorted(glob.glob(pat))
        if m: return m[0]
    sys.exit('no ESP32 serial port found (looked for cu.usbserial-*, cu.wchusbserial*, cu.usbmodem*)')


def open_serial(port: str, baud: int = 115200) -> int:
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


def read_until(fd: int, marker: bytes, timeout: float) -> tuple[bytes, int]:
    buf = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        chunk = read_some(fd)
        if chunk:
            buf.extend(chunk)
            idx = buf.find(marker)
            if idx >= 0:
                return bytes(buf), idx
        else:
            time.sleep(0.01)
    raise TimeoutError(f'timeout waiting for {marker!r} (got {len(buf)} bytes)')


def rgb565le_to_rgb888(buf: bytes, w: int, h: int) -> bytes:
    if len(buf) != w * h * 2:
        raise ValueError(f'expected {w*h*2} bytes for {w}x{h} RGB565, got {len(buf)}')
    out = bytearray(w * h * 3)
    o = 0
    for i in range(0, len(buf), 2):
        v = buf[i] | (buf[i+1] << 8)
        r5 = (v >> 11) & 0x1F
        g6 = (v >>  5) & 0x3F
        b5 =  v        & 0x1F
        # Replicate top bits into low bits so 0x1F → 0xFF, not 0xF8
        out[o]   = (r5 << 3) | (r5 >> 2)
        out[o+1] = (g6 << 2) | (g6 >> 4)
        out[o+2] = (b5 << 3) | (b5 >> 2)
        o += 3
    return bytes(out)


def write_png(path: str, w: int, h: int, rgb: bytes) -> None:
    def chunk(typ: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + typ + data + struct.pack('>I', zlib.crc32(typ + data))
    sig  = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)  # 8-bit per channel, color type 2 = RGB
    raw  = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)  # filter: none
        raw.extend(rgb[y * stride:(y + 1) * stride])
    idat = zlib.compress(bytes(raw), 6)
    with open(path, 'wb') as f:
        f.write(sig)
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', idat))
        f.write(chunk(b'IEND', b''))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--port', default=None, help='serial port (default: first cu.usbserial-*)')
    ap.add_argument('--out',  default='screenshot.png', help='output PNG path')
    ap.add_argument('--timeout', type=float, default=15.0, help='seconds to wait for full frame')
    ap.add_argument('--settle',  type=float, default=2.0,  help='seconds to drain log noise before sending command')
    ap.add_argument('-v', '--verbose', action='store_true', help='print everything received from the device')
    args = ap.parse_args()

    port = args.port or find_port()
    print(f'screenshot: port={port}', file=sys.stderr)

    fd = open_serial(port)
    try:
        # Drain log noise so we don't confuse pre-existing output with our
        # screenshot frame. Capture what we drained — if the user hasn't
        # flashed the new firmware yet, this is the only useful diagnostic.
        drained = bytearray()
        end_settle = time.monotonic() + args.settle
        while time.monotonic() < end_settle:
            chunk = read_some(fd)
            if chunk: drained.extend(chunk)
            else: time.sleep(0.02)
        if args.verbose and drained:
            sys.stderr.write(f'[drained {len(drained)} bytes before send]\n')
            sys.stderr.write(drained.decode('utf-8', errors='replace'))
            sys.stderr.write('\n')

        os.write(fd, b'screenshot\n')

        try:
            buf, idx = read_until(fd, SCR_BEGIN, timeout=args.timeout)
        except TimeoutError as e:
            # If we got SOME bytes, firmware is alive but isn't responding to
            # our command — most likely it's the old build. If we got nothing
            # AND drained nothing earlier, the port itself is suspect.
            sys.stderr.write(f'\nERROR: {e}\n')
            sys.stderr.write(f'pre-send drain: {len(drained)} bytes\n')
            if drained:
                sys.stderr.write('  ' + drained.decode("utf-8", errors="replace").replace("\n", "\n  ") + '\n')
            sys.stderr.write('\nlikely causes:\n')
            sys.stderr.write('  • new firmware not flashed yet:\n')
            sys.stderr.write('      cd src/outputs/esp32 && pio run -e m5stickc-plus -t upload\n')
            sys.stderr.write('  • another process owns the port (pio monitor, screen, VS Code serial)\n')
            sys.stderr.write('  • device asleep — wake it (button press) and retry\n')
            sys.exit(1)
        # Need the full header line (...>>) before parsing.
        post = bytearray(buf[idx:])
        deadline = time.monotonic() + args.timeout
        while b'>>' not in post:
            if time.monotonic() > deadline:
                sys.exit('timeout reading screenshot header')
            chunk = read_some(fd)
            if chunk: post.extend(chunk)
            else:     time.sleep(0.005)
        hdr_end = post.find(b'>>')
        header = bytes(post[:hdr_end + 2]).decode('utf-8', errors='replace')
        m = re.search(r'W=(\d+)\s+H=(\d+)(?:\s+ROT=(\d+))?', header)
        if not m:
            sys.exit(f'unparseable header: {header!r}')
        w   = int(m.group(1))
        h   = int(m.group(2))
        rot = int(m.group(3)) if m.group(3) else 0

        body = bytearray(post[hdr_end + 2:])
        deadline = time.monotonic() + args.timeout
        while SCR_END not in body:
            if time.monotonic() > deadline:
                sys.exit(f'timeout reading screenshot body ({len(body)} bytes so far)')
            chunk = read_some(fd)
            if chunk: body.extend(chunk)
            else:     time.sleep(0.01)

        end = body.find(SCR_END)
        # Strip everything that isn't a base64 char so any stray log lines
        # interleaved between BEGIN and END don't corrupt the decode.
        b64body = re.sub(rb'[^A-Za-z0-9+/=]', b'', bytes(body[:end]))
        raw = base64.b64decode(b64body)

        expected = w * h * 2
        if len(raw) != expected:
            sys.exit(f'decoded {len(raw)} bytes, expected {expected} ({w}x{h} RGB565)')

        rgb = rgb565le_to_rgb888(raw, w, h)
        write_png(args.out, w, h, rgb)
        print(f'screenshot: wrote {args.out} ({w}x{h}, rot={rot})')
    finally:
        os.close(fd)


if __name__ == '__main__':
    main()
