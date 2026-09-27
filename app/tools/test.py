#!/usr/bin/env python3
"""Run the Swift tests. Without full Xcode, BoopTests is an executable over
the XCTest shim (see Package.swift): generate its runner, build the whole
package in one `swift build` (as `make build` does, so nothing is planned or
built twice), then run it. With real XCTest, `swift test`."""
import os
from pathlib import Path
import subprocess
import sys

APP = Path(__file__).resolve().parents[1]


def uses_shim() -> bool:
    """The same test as Package.swift's `useXCTestShim`."""
    if os.environ.get("BOOP_USE_XCTEST_SHIM") == "1":
        return True
    developer = os.environ.get("DEVELOPER_DIR", "/Library/Developer/CommandLineTools")
    modules = [
        "Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule",
        "Library/Developer/Frameworks/XCTest.framework/Modules/XCTest.swiftmodule",
    ]
    return not any(Path(developer, m).exists() for m in modules)


def main() -> int:
    if not uses_shim():
        return subprocess.run(["swift", "test"], cwd=APP).returncode
    subprocess.run([sys.executable, str(APP / "tools/gen-test-runner.py")], check=True)
    built = subprocess.run(["swift", "build"], cwd=APP).returncode
    if built:
        return built
    return subprocess.run([str(APP / ".build/debug/BoopTests")], cwd=APP).returncode


if __name__ == "__main__":
    sys.exit(main())
