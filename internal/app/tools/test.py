#!/usr/bin/env python3
"""Run the Swift tests. Without full Xcode, BoopTests is an executable over
the XCTest shim (see Package.swift): generate its runner, build the whole
package in one `swift build` (as `make build` does, so nothing is planned or
built twice), then run it. With real XCTest, `swift test`."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
# An import of a target that isn't a declared dependency fails the build, so
# app/ can't reach internal/ code. The Makefile's SWIFT_CHECK is the same
# flag, so both run the same build; change the two together.
CHECK = ["--explicit-target-dependency-import-check", "error"]


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
        return subprocess.run(["swift", "test", *CHECK], cwd=ROOT).returncode
    subprocess.run([sys.executable, str(ROOT / "internal/app/tools/gen-test-runner.py")], check=True)
    built = subprocess.run(["swift", "build", *CHECK], cwd=ROOT).returncode
    if built:
        return built
    return subprocess.run([str(ROOT / ".build/debug/BoopTests")], cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main())
