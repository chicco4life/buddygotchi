#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path

Import("env")


def git_sha() -> str:
    root = Path(env.subst("$PROJECT_DIR")).resolve()
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short=12", "HEAD"],
            cwd=root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return "unknown"


def without_defines(flags, names):
    filtered = []
    prefixes = tuple(f"-D{name}=" for name in names)
    exact = {f"-D{name}" for name in names}
    for flag in flags:
        value = str(flag)
        if value in exact or value.startswith(prefixes):
            continue
        filtered.append(flag)
    return filtered


sha = os.environ.get("BUDDY_GIT_SHA") or git_sha()
version = os.environ.get("BUDDY_FW_VERSION") or f"dev+{sha}"

os.environ["BUDDY_GIT_SHA"] = sha
os.environ["BUDDY_FW_VERSION"] = version

env.Replace(BUILD_FLAGS=without_defines(env.get("BUILD_FLAGS", []), {"FW_VERSION", "GIT_SHA"}))
env.Append(BUILD_FLAGS=[f'-DFW_VERSION=\\"{version}\\"', f'-DGIT_SHA=\\"{sha}\\"'])

print(f"Buddygotchi firmware version: {version} ({sha})")
