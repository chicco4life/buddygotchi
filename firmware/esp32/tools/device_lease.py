"""Machine-wide cooperative lease for the single development device."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import secrets
import sys

LOCK = Path('/tmp') / f'boop-device-{os.getuid()}.lock'
OWNER = LOCK.with_suffix('.json')


@contextmanager
def reserve():
    with LOCK.open('a') as handle:
        token = os.environ.get('BOOP_DEVICE_LEASE')
        try:
            owner = json.loads(OWNER.read_text())
        except (OSError, ValueError):
            owner = {}
        if token and token == owner.get('token'):
            # A token only delegates an actively held lease.
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                yield token
                return
            fcntl.flock(handle, fcntl.LOCK_UN)
        print('Waiting for the shared ESP32 reservation…', flush=True, file=sys.stderr)
        fcntl.flock(handle, fcntl.LOCK_EX)
        token = secrets.token_hex(24)
        OWNER.write_text(json.dumps({'pid': os.getpid(), 'token': token, 'cwd': os.getcwd()}))
        OWNER.chmod(0o600)
        try:
            yield token
        finally:
            OWNER.unlink(missing_ok=True)
            fcntl.flock(handle, fcntl.LOCK_UN)
