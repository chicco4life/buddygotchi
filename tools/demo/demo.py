#!/usr/bin/env python3
"""Presenter-controlled, device-only mock demo. No app, hooks, BLE or NVS writes."""
from __future__ import annotations

import argparse
from copy import deepcopy
from dataclasses import dataclass
import json
from pathlib import Path
import secrets
import select
import signal
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
# Reuse the existing serial client and the same hardware/GUI exclusion locks.
sys.path.insert(0, str(ROOT / 'firmware/esp32/tools'))
sys.path.insert(0, str(ROOT / 'tools/dev'))
from buddyctl import SerialBuddy
from device import gui_claim, gui_running
from device_lease import reserve


@dataclass
class Scene:
    cue: str
    frame: dict
    seconds: float | None = None  # None means presenter advances with Enter.


def frame(state='asleep', **extra):
    return dict(v=2, state=state, effort='light', cheer='', uhoh='', overlay='',
                posture='desk', focus=False, **extra)


def task(state, title, **extra):
    status = {'idle': 0, 'working': 1, 'needsYou': 2, 'uhoh': 3, 'done': 0}[state]
    return frame(state, agents=[dict(source='claude-code', working=int(state == 'working'),
                                    idle=int(state in ('idle', 'done')))],
                 threads=[[1, status, title]], threadTotal=1, **extra)


def moment(kind, text, full=False):
    return dict(id=secrets.randbelow(2**32-1)+1, kind=kind,
                tier='full' if full else 'caption',
                expression='pull' if full else ('nod' if kind == 'start' else 'pleased'),
                text=text, count=1, age=0,
                left=1500 if kind == 'start' else (5000 if full else 4000))


def flows():
    def start(title, words='On it!'):
        return Scene('Task started: brief acknowledgement.',
                     task('working', title, moment=moment('start', words)), 1.5)
    def work(title, seconds):
        return Scene('Working: watch the sweating face.', task('working', title), seconds)
    def done(title, full=False):
        return Scene('Turn completed: watch the words arrive.',
                     task('done', title, moment=moment('completed', 'All done!', full)),
                     5.5 if full else 4.5)
    return {
        'success': [Scene('SUCCESS — "You can glance over and know when work finishes."', frame()),
                    start('Polish the page'), work('Polish the page', 3),
                    done('Polish the page', True),
                    Scene('Finished. Tap the face to view the mock task, then Enter to end.',
                          task('idle', 'Polish the page'))],
        'failure': [Scene('FAILURE + RECOVERY — "Trouble gets a reaction, and retry clears it."', frame()),
                    start('Fix the build'), work('Fix the build', 3),
                    Scene('Explicit failure. Explain the red/slumped face; Enter starts a mock retry.',
                          {**task('uhoh', 'Fix the build'), 'uhoh': 'error'}),
                    start('Fix the build', 'Trying again!'), work('Fix the build', 3),
                    done('Fix the build'),
                    Scene('Recovered. Enter to end this story.', task('idle', 'Fix the build'))],
        'attention': [Scene('NEEDS YOU — "Come back when your agent has a question."', frame()),
                      start('Update the homepage'), work('Update the homepage', 3),
                      Scene('Question: Which layout? Enter simulates the answer. Device taps only dismiss the reminder.',
                            task('needsYou', 'Update the homepage',
                                 card=dict(id='demo-'+secrets.token_hex(4), tool='Question',
                                           gloss='Which layout?', n=1, of=1))),
                      Scene('Mock answer received: work resumes.', task('working', 'Update the homepage'), 3),
                      done('Update the homepage'),
                      Scene('Question resolved and turn finished. Enter to end.', task('idle', 'Update the homepage'))],
    }


# Allowlist prevents demo edits from adding persistent snapshots, cosmetics,
# clock synchronization, commands, OTA or pairing operations.
ALLOWED = {'v', 'state', 'effort', 'cheer', 'uhoh', 'overlay', 'posture', 'focus',
           'agents', 'threads', 'threadTotal', 'moment', 'card'}
PRESERVED = ('mute', 'snapName', 'snapTasks', 'skin', 'accessory', 'silhouette',
             'level', 'streak', 'firstWake')


def encode(value, mute):
    if set(value) - ALLOWED:
        raise ValueError('Demo frame contains a non-transient field')
    # Missing mute defaults to zero in the firmware: always carry its existing value.
    value = {**value, 'mute': mute}
    wire = json.dumps(value, ensure_ascii=True, separators=(',', ':'))
    if len(wire.encode()) + 1 > 1536:
        raise ValueError('Demo frame exceeds wire budget')
    return wire


def at_age(value, elapsed):
    value = deepcopy(value)
    if 'moment' in value:
        m = value['moment']
        age = max(0, int(elapsed * 1000))
        if age >= m['left']:
            del value['moment']
        else:
            m['age'], m['left'] = age, m['left'] - age
    return value


class Device:
    def __init__(self, serial):
        self.serial = serial
        info = serial.framed_json('ping', 'PONG', 3)
        if info.get('board') != 'ws-amoled164' or info.get('contract') != 2 or info.get('usbOnly') is not False:
            raise RuntimeError('Demo requires normal ws-amoled164 v2 firmware; no flashing is performed.')
        self.before = self.state()
        if self.before.get('firstWake', True) or self.before.get('frozen', True):
            raise RuntimeError('Finish normal first wake / clear an existing debug clock before the demo.')
        if not all(key in self.before for key in PRESERVED):
            raise RuntimeError('Firmware is missing preservation telemetry.')
        if 'momentVisible' not in self.before:
            raise RuntimeError('Install the turn-moment firmware first.')

    def state(self):
        return self.serial.framed_json('state', 'STATE', 3)

    def send(self, value):
        self.serial.write_line(encode(value, self.before['mute']))
        got = self.state()  # Acknowledges processing of the preceding serial line.
        if got['badFrames'] != self.before['badFrames'] or got['creature'] != value['state']:
            raise RuntimeError('Device rejected a frame or another writer changed it.')
        return got

    def reset(self):
        self.send(frame())
        got = self.state()
        if got.get('screenOff') or got.get('napping'):
            self.serial.write_line('press a 100')
        # Local affection and travel stats can outlive a frame; let them expire.
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            got = self.send(frame())
            if (got.get('layer') == 'face' and not got.get('cardId')
                    and not got.get('momentVisible') and not got.get('bubble')
                    and not got.get('threadCount') and not got.get('recentCount')
                    and not got.get('screenOff') and not got.get('napping')):
                if any(got.get(k) != self.before[k] for k in PRESERVED):
                    raise RuntimeError('Saved-state telemetry changed; inspect the device before continuing.')
                return
            time.sleep(.2)
        raise RuntimeError('Could not verify a clear sleeping face. Place device face-up and run --reset-only.')


def play(scene, device, automatic=False):
    print('\n' + scene.cue, flush=True)
    if scene.seconds is None:
        print('Enter to continue · Ctrl-C to finish and clean up', flush=True)
    else:
        print(f'({scene.seconds:g} seconds)', flush=True)
    start = time.monotonic()
    duration = scene.seconds if scene.seconds is not None else (2 if automatic else None)
    while True:
        device.send(at_age(scene.frame, time.monotonic() - start))
        remaining = None if duration is None else duration - (time.monotonic() - start)
        if remaining is not None and remaining <= 0:
            return
        delay = 1 if remaining is None else min(1, remaining)
        if scene.seconds is None and not automatic:
            ready, _, _ = select.select([sys.stdin], [], [], delay)
            if ready:
                if not sys.stdin.readline():
                    raise EOFError('Presenter input closed')
                return
        else:
            time.sleep(delay)


def run(device, selected, automatic=False):
    try:
        device.reset()
        for name in selected:
            for scene in flows()[name]:
                play(scene, device, automatic)
            device.reset()
    finally:
        # A second Ctrl-C must not interrupt the bounded cleanup attempt.
        previous = {s: signal.signal(s, signal.SIG_IGN) for s in (signal.SIGINT, signal.SIGTERM)}
        try:
            device.reset()
            print('\nCleanup verified: sleeping face, no demo requests/text/tasks; saved settings preserved.')
        finally:
            for s, handler in previous.items():
                signal.signal(s, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('flow', nargs='?', choices=['success', 'failure', 'attention', 'all'], default='all')
    parser.add_argument('--port', help='Explicit USB serial port (recommended with multiple devices)')
    parser.add_argument('--preview', action='store_true', help='Print scenes without accessing any device')
    parser.add_argument('--auto', action='store_true', help='Advance presenter pauses after 2 seconds')
    parser.add_argument('--reset-only', action='store_true', help='Clear transient demo state after an interrupted connection')
    args = parser.parse_args()
    selected = list(flows()) if args.flow == 'all' else [args.flow]
    if args.preview:
        for name in selected:
            for scene in flows()[name]:
                print(f'[{name}] {scene.cue} ({scene.seconds or "Enter"})')
                encode(scene.frame, 1)
        return 0
    if not args.auto and not args.reset_only and not sys.stdin.isatty():
        parser.error('Interactive demo needs a terminal; use --auto or --preview.')
    def interrupt(signum, _):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    try:
        with gui_claim(), reserve():
            if gui_running():
                raise RuntimeError('Quit Boop before running the demo. Reopen it yourself afterward.')
            with SerialBuddy(args.port, timeout=5) as serial:
                device = Device(serial)
                run(device, [] if args.reset_only else selected, args.auto)
    except (KeyboardInterrupt, EOFError):
        print('\nDemo stopped.')
        return 130
    except Exception as exc:
        print(f'\nDemo error: {exc}\nIf USB was disconnected, reconnect it and run this script with --reset-only.', file=sys.stderr)
        return 1
    print('Reopen your normal Boop app to resume live work.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
