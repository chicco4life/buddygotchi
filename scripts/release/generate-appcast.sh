#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 VERSION" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/Buddygotchi-$VERSION.dmg"
APPCAST_DIR="$DIST_DIR/appcast"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/chicco4life/buddygotchi/releases/download/v$VERSION}"
PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:-}"

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" && -x "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    echo "$SPARKLE_GENERATE_APPCAST"
    return
  fi

  for candidate in \
    "$REPO_ROOT/app/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$REPO_ROOT/app/.build/checkouts/Sparkle/bin/generate_appcast" \
    "/Applications/Sparkle.app/Contents/MacOS/generate_appcast" \
    "/opt/homebrew/bin/generate_appcast" \
    "/usr/local/bin/generate_appcast"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  if command -v generate_appcast >/dev/null 2>&1; then
    command -v generate_appcast
    return
  fi

  echo "generate_appcast not found. Set SPARKLE_GENERATE_APPCAST to Sparkle's generate_appcast tool." >&2
  exit 69
}

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 66
fi

if [[ -z "$PRIVATE_KEY_PATH" || ! -f "$PRIVATE_KEY_PATH" ]]; then
  echo "SPARKLE_PRIVATE_KEY_PATH must point to the Sparkle EdDSA private key file" >&2
  exit 64
fi

rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$DMG_PATH" "$APPCAST_DIR/"

GENERATE_APPCAST="$(find_generate_appcast)"
echo "==> Generating appcast with $GENERATE_APPCAST"
"$GENERATE_APPCAST" \
  --ed-key-file "$PRIVATE_KEY_PATH" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$APPCAST_DIR"

cp "$APPCAST_DIR/appcast.xml" "$DIST_DIR/appcast.xml"
echo "Generated $DIST_DIR/appcast.xml"
