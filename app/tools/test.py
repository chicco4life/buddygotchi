#!/usr/bin/env python3
"""Run the test target selected by Package.swift, including the CLT shim."""
import json
from pathlib import Path
import subprocess
import sys


def main():
    app = Path(__file__).resolve().parents[1]
    package = json.loads(subprocess.check_output(
        ["swift", "package", "describe", "--type", "json"], cwd=app
    ))
    target = next(t for t in package["targets"] if t["name"] == "BoopTests")
    if target["type"] == "executable":
        subprocess.run([sys.executable, str(app / "tools/gen-test-runner.py")], check=True)
        command = ["swift", "run", "BoopTests"]
    elif target["type"] == "test":
        command = ["swift", "test"]
    else:
        raise RuntimeError(f"Unsupported BoopTests target type: {target['type']}")
    return subprocess.run(command, cwd=app).returncode


if __name__ == "__main__":
    sys.exit(main())
