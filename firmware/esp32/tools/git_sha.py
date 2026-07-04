from pathlib import Path
import subprocess

Import("env")


def git_sha():
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


env.Append(BUILD_FLAGS=[f'-DGIT_SHA=\\"{git_sha()}\\"'])
