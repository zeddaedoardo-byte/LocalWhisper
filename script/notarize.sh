#!/usr/bin/env bash
set -euo pipefail

# Notarizes the release bundle and DMG with Apple, then staples the tickets
# so the app launches without the Gatekeeper "unidentified developer" prompt
# on any other Mac.
#
# Prerequisites (one-off, performed by the developer):
#   1. Apple Developer Program enrollment ($99 / year).
#   2. A "Developer ID Application" certificate created in
#      https://developer.apple.com/account/resources/certificates and
#      installed in the login keychain.
#   3. An app-specific password generated at https://appleid.apple.com.
#   4. Stored credentials in the keychain so notarytool can find them:
#
#        xcrun notarytool store-credentials lwf-notary \
#          --apple-id "<your-apple-id>" \
#          --team-id "<your-team-id>" \
#          --password "<app-specific-password>"
#
#      Then export NOTARY_PROFILE="lwf-notary" before running this script.
#
# Usage:
#   ./script/notarize.sh
#
# Optional env:
#   NOTARY_PROFILE  notarytool keychain profile name (default: lwf-notary)
#   LWF_VERSION     short version string used to find the DMG (default: 0.2.0)

PROFILE="${NOTARY_PROFILE:-lwf-notary}"
SHORT_VERSION="${LWF_VERSION:-0.2.0}"
APP_NAME="LocalWhisper"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="/private/tmp/local-whisperflow-release/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$SHORT_VERSION.dmg"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Run ./script/build_release.sh first." >&2
  exit 1
fi

if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "Developer ID Application:"; then
  echo "No Developer ID Application certificate found in the login keychain." >&2
  echo "Create one at https://developer.apple.com/account/resources/certificates and install it." >&2
  exit 1
fi

CDV="$(codesign -dv "$APP_BUNDLE" 2>&1 | grep -E '^Authority=Developer ID Application' | head -1 || true)"
if [[ -z "$CDV" ]]; then
  echo "App bundle is not signed with Developer ID Application. Re-run build_release.sh after the cert is installed." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "notarytool keychain profile '$PROFILE' not found." >&2
  echo "Set it up with:" >&2
  echo "  xcrun notarytool store-credentials \"$PROFILE\" \\" >&2
  echo "    --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
  exit 1
fi

echo "==> Zipping app bundle for upload"
ZIP_PATH="/private/tmp/local-whisperflow-release/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Submitting app to notarization (this can take a few minutes)"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait --output-format plist)"
echo "$SUBMIT_OUTPUT"
STATUS="$(echo "$SUBMIT_OUTPUT" | /usr/libexec/PlistBuddy -c "Print :status" /dev/stdin 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization failed (status: $STATUS). Inspect the log above." >&2
  exit 1
fi

echo "==> Stapling app bundle"
xcrun stapler staple "$APP_BUNDLE"

if [[ -f "$DMG_PATH" ]]; then
  echo "==> Submitting DMG to notarization"
  SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait --output-format plist)"
  echo "$SUBMIT_OUTPUT"
  STATUS="$(echo "$SUBMIT_OUTPUT" | /usr/libexec/PlistBuddy -c "Print :status" /dev/stdin 2>/dev/null || true)"
  if [[ "$STATUS" == "Accepted" ]]; then
    echo "==> Stapling DMG"
    xcrun stapler staple "$DMG_PATH"
  else
    echo "DMG notarization failed (status: $STATUS)." >&2
    exit 1
  fi
fi

echo
echo "Done. The app and DMG are notarized."
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
