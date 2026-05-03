#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LocalWhisper"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_APP="/Applications/$APP_NAME.app"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "\033[32m✓\033[0m %s\n" "$*"; }
err()  { printf "\033[31m✗\033[0m %s\n" "$*" >&2; }

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command '$cmd' is missing."
    case "$cmd" in
      cmake) err "  Install with: brew install cmake" ;;
      swift) err "  Install Xcode Command Line Tools: xcode-select --install" ;;
      git)   err "  Install Xcode Command Line Tools: xcode-select --install" ;;
    esac
    exit 1
  fi
}

bold "==> Checking prerequisites"
require_command swift
require_command cmake
require_command git
require_command codesign
require_command security

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  err "This app targets Apple Silicon (arm64). Detected: $ARCH"
  err "It may build but Metal acceleration will be unavailable. Continuing anyway."
fi

OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$OS_MAJOR" -lt 14 ]]; then
  err "macOS 14 (Sonoma) or newer is required. Detected: $(sw_vers -productVersion)"
  exit 1
fi
ok "macOS $(sw_vers -productVersion) on $ARCH"

bold "==> Building whisper.cpp + downloading model"
echo "    This step can take 5-15 minutes the first time (model is ~3 GB)."
"$ROOT_DIR/script/setup_whisper_cpp.sh"
ok "whisper.cpp ready"

bold "==> Building $APP_NAME (release)"
"$ROOT_DIR/script/build_release.sh"
ok "Release bundle built"

BUILD_BUNDLE="$ROOT_DIR/dist/release/$APP_NAME.app"
if [[ ! -d "$BUILD_BUNDLE" ]]; then
  err "Expected bundle missing: $BUILD_BUNDLE"
  exit 1
fi

bold "==> Installing to /Applications"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" || true
  sleep 1
fi

if [[ -d "$TARGET_APP" ]]; then
  if [[ -w "/Applications" ]]; then
    rm -rf "$TARGET_APP"
  else
    sudo rm -rf "$TARGET_APP"
  fi
fi

if [[ -w "/Applications" ]]; then
  cp -R "$BUILD_BUNDLE" "$TARGET_APP"
else
  sudo cp -R "$BUILD_BUNDLE" "$TARGET_APP"
fi
ok "Installed at $TARGET_APP"

bold "==> Done"
echo
echo "Launch the app:"
echo "  open '$TARGET_APP'"
echo
echo "On first launch macOS will ask for two permissions:"
echo "  · Microphone (to record audio)"
echo "  · Accessibility (to capture the global hotkey and to auto-paste)"
echo
echo "Default hotkey is fn-hold. Change it in Settings → Hotkey."
echo
echo "If macOS Gatekeeper blocks the first launch:"
echo "  right-click the app in /Applications → Open → confirm."
