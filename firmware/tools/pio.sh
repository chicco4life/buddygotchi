#!/bin/sh
# Runs PlatformIO with its core and packages inside this checkout, so
# worktrees don't fight over one shared cache. All paths are git-ignored.
#   firmware/tools/pio.sh run -e cyd24
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$firmware_dir/.platformio-core}"
cd "$firmware_dir"
exec "$(command -v pio || echo /opt/homebrew/bin/pio)" "$@"
