#!/bin/sh
# pio wrapper for the ws-amoled164* envs (Waveshare ESP32-S3 AMOLED board).
#
# Those envs build on the pioarduino platform (Arduino core 3.x) while the
# M5 envs use PlatformIO's espressif32 (core 2.x). Both platforms manage a
# package named framework-arduinoespressif32, and building one platform
# invalidates the other's copy in the shared ~/.platformio/packages tree —
# the first pioarduino build after any M5 build then fails with a missing
# FRAMEWORK_DIR. An isolated package tree makes the two platforms
# invisible to each other. Costs one extra toolchain download (~1GB) the
# first time, then it's warm.
#
# Usage, from firmware/esp32/:
#   tools/pio_ws.sh run -e ws-amoled164 [-t upload]
#   tools/pio_ws.sh run -e ws-amoled164-spike -t upload
export PLATFORMIO_PACKAGES_DIR="${PLATFORMIO_PACKAGES_DIR:-$HOME/.platformio/packages-pioarduino}"
exec pio "$@"
