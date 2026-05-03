#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Resources"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$RES_DIR"

# 1. Render 1024x1024 master via Swift one-shot.
SOURCE_PNG="$RES_DIR/icon-source.png"
swift "$ROOT_DIR/Tools/icon-renderer/main.swift" "$SOURCE_PNG"

# 2. Build iconset.
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

declare -a SIZES=(16 32 64 128 256 512 1024)
for sz in "${SIZES[@]}"; do
  /usr/bin/sips -Z "$sz" "$SOURCE_PNG" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  if [[ "$sz" -le 512 ]]; then
    dbl=$((sz * 2))
    /usr/bin/sips -Z "$dbl" "$SOURCE_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  fi
done

# 3. Convert to .icns.
/usr/bin/iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"

echo "Wrote $RES_DIR/AppIcon.icns"
