#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-}"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "Usage: $0 path/to/Buddygotchi-VERSION.dmg" >&2
  exit 64
fi

NOTARY_ARGS=()
if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE")
else
  : "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
  : "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"
  : "${APPLE_NOTARY_KEY_PATH:?APPLE_NOTARY_KEY_PATH is required}"
  NOTARY_ARGS=(--key "$APPLE_NOTARY_KEY_PATH" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")
fi

echo "==> Submitting $DMG_PATH for notarization"
xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Notarized and stapled $DMG_PATH"
