#!/usr/bin/env python3
"""Compatibility wrapper for buddyctl.py btn."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    buddyctl = Path(__file__).with_name("buddyctl.py")
    return subprocess.call([sys.executable, str(buddyctl), "btn", *sys.argv[1:]])


if __name__ == "__main__":
    raise SystemExit(main())
