#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="$ROOT_DIR/external/whisper.cpp"
MODEL_DIR="$ROOT_DIR/Models"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build"
cmake --build "$WHISPER_DIR/build" -j --config Release

mkdir -p "$MODEL_DIR"
"$WHISPER_DIR/models/download-ggml-model.sh" large-v3 "$MODEL_DIR"

echo "whisper-cli: $WHISPER_DIR/build/bin/whisper-cli"
echo "model: $MODEL_DIR/ggml-large-v3.bin"
