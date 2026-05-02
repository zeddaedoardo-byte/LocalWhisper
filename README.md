# LocalWhisperFlow

LocalWhisperFlow is a local macOS menu bar dictation app inspired by WhisperFlow. It records microphone audio with Control push-to-talk, transcribes it offline on Apple Silicon (Metal) via a persistent `whisper.cpp` server using Whisper Large V3, then copies the transcript to the clipboard and optionally pastes it into the active app.

## Requirements

- macOS 14+ on Apple Silicon
- Xcode command line tools / Swift toolchain
- Homebrew `cmake` for building `whisper.cpp`
- Microphone permission
- Accessibility permission for Control push-to-talk and auto-paste

## Setup

```bash
./script/setup_whisper_cpp.sh
```

This clones and statically builds `whisper.cpp` under `external/whisper.cpp` (Metal + Accelerate enabled) and downloads Whisper Large V3 to:

```text
~/Library/Application Support/LocalWhisperFlow/Models/ggml-large-v3.bin
```

The model is ~2.9 GiB. It must NOT live inside iCloud Drive — iCloud lazy-load makes the first model load take minutes. Application Support is local-only, so cold start is ~5–10 s on M-series.

## Run

```bash
./script/build_and_run.sh
```

The app runs as a menu bar app. Hold Control to record. Release Control to stop and transcribe. Transcript is copied to the clipboard; with Accessibility permission it is also pasted into the active app.

On launch the app spawns `whisper-server` and warms up the model in the background. After warmup, every subsequent dictation is fast (~2–3 s for short utterances) because the model stays resident.

The run script builds SwiftPM artifacts under `/private/tmp/local-whisperflow-swiftpm-build` so iCloud Drive does not sync compiler output while Swift is linking.

## Test

```bash
swift test --scratch-path /private/tmp/local-whisperflow-swiftpm-build
```

## Notes

- Apple Silicon: Metal + embedded Metal library + Accelerate BLAS. No `-ng` fallback.
- Persistent worker: `whisper-server` is started by the app and kept alive; the app talks to it via HTTP on `127.0.0.1:18642`.
- Cold start is dominated by the 3 GiB model load. The model lives in Application Support (not iCloud) to keep cold start fast.
- Auto-paste failures do not discard the transcript; text remains in the clipboard.
- Global Control push-to-talk requires Accessibility permission and uses a global `CGEvent` tap so modifier-only press/release is captured reliably.
