#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="$ROOT_DIR/external/whisper.cpp"
MODEL_DIR="$HOME/Library/Application Support/LocalWhisperFlow/Models"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

rm -rf "$WHISPER_DIR/build"
cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_ACCELERATE=ON \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=ON
cmake --build "$WHISPER_DIR/build" -j --config Release

mkdir -p "$MODEL_DIR"
if [[ ! -f "$MODEL_DIR/ggml-large-v3.bin" ]]; then
  "$WHISPER_DIR/models/download-ggml-model.sh" large-v3 "$MODEL_DIR"
fi

echo "whisper-cli:    $WHISPER_DIR/build/bin/whisper-cli"
echo "whisper-server: $WHISPER_DIR/build/bin/whisper-server"
echo "model:          $MODEL_DIR/ggml-large-v3.bin"
