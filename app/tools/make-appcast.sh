#!/usr/bin/env bash
set -euo pipefail

# Generate Boop's Sparkle appcast from a downloads directory.
# Usage: make-appcast.sh <sparkle-bin-dir> <downloads-dir>
# Example: app/tools/make-appcast.sh ./sparkle/bin ./downloads

usage() {
  echo "usage: make-appcast.sh <sparkle-bin-dir> <downloads-dir>" >&2
}

if [[ "$#" -ne 2 ]]; then
  usage
  exit 64
fi

SPARKLE_BIN_DIR="$1"
DOWNLOADS_DIR="$2"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "error: generate_appcast not found or not executable at $GENERATE_APPCAST" >&2
  exit 1
fi

if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  echo "error: downloads directory not found: $DOWNLOADS_DIR" >&2
  exit 1
fi

exec "$GENERATE_APPCAST" "$DOWNLOADS_DIR"
