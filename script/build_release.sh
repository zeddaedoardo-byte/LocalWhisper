#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LocalWhisperFlow"
BUNDLE_ID="com.local.LocalWhisperFlow"
MIN_SYSTEM_VERSION="14.0"
SHORT_VERSION="${LWF_VERSION:-0.2.0}"
BUILD_NUMBER="${LWF_BUILD:-$(date +%Y%m%d%H%M)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_BUILD_DIR="/private/tmp/local-whisperflow-release-build"
STAGE_DIR="/private/tmp/local-whisperflow-release"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$SHORT_VERSION.dmg"

echo "==> Building release binary"
swift build -c release --scratch-path "$SWIFT_BUILD_DIR"
BUILD_BINARY="$(swift build -c release --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)/$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$STAGE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

WHISPER_BIN_DIR="$ROOT_DIR/external/whisper.cpp/build/bin"
if [[ -x "$WHISPER_BIN_DIR/whisper-cli" && -x "$WHISPER_BIN_DIR/whisper-server" ]]; then
  echo "==> Embedding whisper.cpp binaries"
  mkdir -p "$APP_RESOURCES/bin"
  cp "$WHISPER_BIN_DIR/whisper-cli" "$APP_RESOURCES/bin/"
  cp "$WHISPER_BIN_DIR/whisper-server" "$APP_RESOURCES/bin/"
  chmod +x "$APP_RESOURCES/bin/whisper-cli" "$APP_RESOURCES/bin/whisper-server"
else
  echo "WARNING: whisper.cpp binaries missing at $WHISPER_BIN_DIR. Run ./script/setup_whisper_cpp.sh first." >&2
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>LocalWhisperFlow</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>LocalWhisperFlow records microphone audio and transcribes it locally with Whisper Large V3.</string>
</dict>
</plist>
PLIST

echo "==> Cleaning extended attributes"
find "$APP_BUNDLE" -print0 | while IFS= read -r -d '' f; do
  xattr -d com.apple.FinderInfo "$f" 2>/dev/null || true
  xattr -d com.apple.fileprovider.fpfs#P "$f" 2>/dev/null || true
done

echo "==> Code signing"
SIGNING_HASH="$(security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Development:/ {print $2; exit}')"
if [[ -n "$SIGNING_HASH" ]]; then
  echo "    using identity: $SIGNING_HASH"
  IDENT_ARG=("--sign" "$SIGNING_HASH")
else
  echo "    no Apple Development identity found, signing ad-hoc"
  IDENT_ARG=("--sign" "-")
fi

# Sign nested binaries first
if [[ -d "$APP_RESOURCES/bin" ]]; then
  for nested in "$APP_RESOURCES"/bin/*; do
    codesign --force "${IDENT_ARG[@]}" --timestamp=none "$nested"
  done
fi
codesign --force "${IDENT_ARG[@]}" --identifier "$BUNDLE_ID" --timestamp=none "$APP_BUNDLE"

echo "==> Building DMG"
DMG_STAGE="/private/tmp/local-whisperflow-dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME $SHORT_VERSION" \
  -srcfolder "$DMG_STAGE" \
  -format UDZO \
  -fs HFS+ \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

# Make staged bundle accessible via repo dist/release symlink for install.sh.
mkdir -p "$RELEASE_DIR"
rm -rf "$RELEASE_DIR/$APP_NAME.app"
ln -s "$APP_BUNDLE" "$RELEASE_DIR/$APP_NAME.app"

rm -rf "$DMG_STAGE"

echo
echo "Done."
echo "  App: $APP_BUNDLE"
echo "       (symlinked at $RELEASE_DIR/$APP_NAME.app)"
echo "  DMG: $DMG_PATH"
