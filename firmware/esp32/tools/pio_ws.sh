#!/bin/sh
# Worktree-local PlatformIO state for the Waveshare/pioarduino toolchain.
# Keep packages separate from M5 builds and from other worktrees. All paths
# are git-ignored; a fresh checkout downloads its own tools on first build.
# Explicit environment overrides remain available for managed CI caches.
# Usage from firmware/esp32: tools/pio_ws.sh run -e ws-amoled164
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$firmware_dir/.platformio-core}"
export PLATFORMIO_PACKAGES_DIR="${PLATFORMIO_PACKAGES_DIR:-$PLATFORMIO_CORE_DIR/packages-pioarduino}"
exec pio "$@"
