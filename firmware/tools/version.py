# PlatformIO pre-script: bakes the firmware version and git SHA into the
# build, so `boopctl ping` can confirm what's flashed.
import subprocess

Import("env")  # noqa: F821

def git(*args):
    try:
        return subprocess.check_output(["git", *args], cwd=env["PROJECT_DIR"], text=True).strip()  # noqa: F821
    except Exception:
        return "unknown"

sha = git("rev-parse", "--short=10", "HEAD")
if git("status", "--porcelain", "--", "."):
    sha += "-dirty"
version = open(env["PROJECT_DIR"] + "/../VERSION").read().strip()  # noqa: F821
env.Append(CPPDEFINES=[("BOOP_FW_VERSION", f'\\"{version}\\"'), ("BOOP_GIT_SHA", f'\\"{sha}\\"')])  # noqa: F821
