#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="$ROOT_DIR/external/whisper.cpp"
MODEL_DIR="$HOME/Library/Application Support/LocalWhisper/Models"
DEFAULT_MODEL="${LWF_DEFAULT_MODEL:-large-v3-turbo}"

ARCH="$(uname -m)"
COREML_FLAGS=()
if [[ "$ARCH" == "arm64" ]]; then
  COREML_FLAGS=(-DWHISPER_COREML=1 -DWHISPER_COREML_ALLOW_FALLBACK=1)
fi

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
  -DWHISPER_BUILD_SERVER=ON \
  "${COREML_FLAGS[@]}"
cmake --build "$WHISPER_DIR/build" -j --config Release

mkdir -p "$MODEL_DIR"

MODEL_FILE="$MODEL_DIR/ggml-$DEFAULT_MODEL.bin"
if [[ ! -f "$MODEL_FILE" ]]; then
  "$WHISPER_DIR/models/download-ggml-model.sh" "$DEFAULT_MODEL" "$MODEL_DIR"
fi

# On Apple Silicon, also fetch the precompiled Core ML encoder for the default
# model so the Apple Neural Engine can be used at first launch.
ENCODER_DIR="$MODEL_DIR/ggml-$DEFAULT_MODEL-encoder.mlmodelc"
if [[ "$ARCH" == "arm64" && ! -d "$ENCODER_DIR" ]]; then
  ENCODER_ZIP="$MODEL_DIR/ggml-$DEFAULT_MODEL-encoder.mlmodelc.zip"
  ENCODER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$DEFAULT_MODEL-encoder.mlmodelc.zip"
  echo "Downloading Core ML encoder from $ENCODER_URL"
  if curl --fail -L -o "$ENCODER_ZIP" "$ENCODER_URL"; then
    /usr/bin/unzip -q -o "$ENCODER_ZIP" -d "$MODEL_DIR"
    rm -f "$ENCODER_ZIP"
    echo "Core ML encoder installed at $ENCODER_DIR"
  else
    echo "WARNING: Could not fetch Core ML encoder. The app will fall back to Metal-only inference."
    rm -f "$ENCODER_ZIP"
  fi
fi

# Always fetch the silero-v5 VAD model so whisper-server can trim leading /
# trailing silence at inference time. ~2 MB.
VAD_NAME="ggml-silero-v5.1.2.bin"
VAD_FILE="$MODEL_DIR/$VAD_NAME"
if [[ ! -f "$VAD_FILE" ]]; then
  VAD_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_NAME"
  echo "Downloading VAD model from $VAD_URL"
  if ! curl --fail -L -o "$VAD_FILE" "$VAD_URL"; then
    echo "WARNING: Could not fetch silero VAD model. The app will run without VAD trimming."
    rm -f "$VAD_FILE"
  fi
fi

echo "whisper-cli:    $WHISPER_DIR/build/bin/whisper-cli"
echo "whisper-server: $WHISPER_DIR/build/bin/whisper-server"
echo "model:          $MODEL_FILE"
if [[ -d "$ENCODER_DIR" ]]; then
  echo "core ml:        $ENCODER_DIR"
fi
if [[ -f "$VAD_FILE" ]]; then
  echo "vad model:      $VAD_FILE"
fi
