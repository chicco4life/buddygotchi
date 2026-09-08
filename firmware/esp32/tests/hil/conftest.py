"""HIL helpers shared by every test module.

Set BUDDY_SERIAL_TEE=/path to append every byte read from the device to a
file. On this board the panic handler prints through the same USB port, so a
teed run is how you catch a backtrace the assertions alone would hide.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import buddyctl  # noqa: E402

_tee = os.environ.get("BUDDY_SERIAL_TEE")
if _tee:
    _log = open(_tee, "ab")
    _orig = buddyctl.SerialBuddy.read_until

    def _teed(self, pred, timeout):
        try:
            buf, m = _orig(self, pred, timeout)
            _log.write(buf); _log.flush()
            return buf, m
        except buddyctl.BuddyError as exc:
            partial = getattr(exc, "buffer", None)
            if partial:
                _log.write(partial); _log.flush()
            raise

    buddyctl.SerialBuddy.read_until = _teed
