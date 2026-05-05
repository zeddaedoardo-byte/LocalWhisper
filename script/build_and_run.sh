#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LocalWhisper"
BUNDLE_ID="com.local.LocalWhisper"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_BUILD_DIR="/private/tmp/local-whisperflow-swiftpm-build"
STAGE_DIR="/private/tmp/local-whisperflow-app"
STAGE_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_BUNDLE="/Applications/$APP_NAME.app"
APP_CONTENTS="$STAGE_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
WHISPER_BIN_DIR="$ROOT_DIR/external/whisper.cpp/build/bin"
SHORT_VERSION="${LWF_VERSION:-0.2.0}"
BUILD_NUMBER="${LWF_BUILD:-$(date +%Y%m%d%H%M)}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f whisper-server >/dev/null 2>&1 || true

swift build --scratch-path "$SWIFT_BUILD_DIR"
BUILD_BINARY="$(swift build --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$STAGE_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

LOCALIZED_RESOURCES_SRC="$ROOT_DIR/Resources/Localizations"
if [[ -d "$LOCALIZED_RESOURCES_SRC" ]]; then
  for lproj in "$LOCALIZED_RESOURCES_SRC"/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "$APP_RESOURCES/"
  done
fi

if [[ -x "$WHISPER_BIN_DIR/whisper-cli" && -x "$WHISPER_BIN_DIR/whisper-server" ]]; then
  mkdir -p "$APP_RESOURCES/bin"
  cp "$WHISPER_BIN_DIR/whisper-cli" "$APP_RESOURCES/bin/"
  cp "$WHISPER_BIN_DIR/whisper-server" "$APP_RESOURCES/bin/"
  chmod +x "$APP_RESOURCES/bin/whisper-cli" "$APP_RESOURCES/bin/whisper-server"
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
  <string>LocalWhisper</string>
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
  <string>LocalWhisper records microphone audio and transcribes it locally with Whisper Large V3 Turbo.</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>it</string>
  </array>
</dict>
</plist>
PLIST

# iCloud Drive can reapply com.apple.FinderInfo on every write; the staging
# dir lives in /private/tmp so it does not, but xattr clean is cheap and stays
# as a safety net for any future move.
find "$STAGE_BUNDLE" -print0 | while IFS= read -r -d '' f; do
  xattr -d com.apple.FinderInfo "$f" 2>/dev/null || true
  xattr -d com.apple.fileprovider.fpfs#P "$f" 2>/dev/null || true
done

SIGNING_HASH="$(security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Development:/ {print $2; exit}')"
if [[ -n "$SIGNING_HASH" ]]; then
  IDENT_ARG=("--sign" "$SIGNING_HASH")
else
  IDENT_ARG=("--sign" "-")
fi

if [[ -d "$APP_RESOURCES/bin" ]]; then
  for nested in "$APP_RESOURCES"/bin/*; do
    codesign --force "${IDENT_ARG[@]}" --timestamp=none "$nested"
  done
fi
codesign --force "${IDENT_ARG[@]}" --identifier "$BUNDLE_ID" --timestamp=none "$STAGE_BUNDLE"

# Replace the running install in /Applications so dev iterations always pick
# up the latest binary, embedded whisper.cpp, localized resources and
# Info.plist. Keeping the stable signing identity means TCC permissions
# survive across rebuilds.
if [[ -d "$APP_BUNDLE" ]]; then
  if [[ -w "/Applications" ]]; then
    rm -rf "$APP_BUNDLE"
  else
    sudo rm -rf "$APP_BUNDLE"
  fi
fi
if [[ -w "/Applications" ]]; then
  cp -R "$STAGE_BUNDLE" "$APP_BUNDLE"
else
  sudo cp -R "$STAGE_BUNDLE" "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
