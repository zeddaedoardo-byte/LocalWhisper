# LocalWhisperFlow

LocalWhisperFlow is a local macOS menu bar dictation app inspired by WhisperFlow. It records microphone audio with a global hotkey, transcribes it offline with `whisper.cpp` and Whisper Large V3, then copies the transcript to the clipboard and optionally pastes it into the active app.

## Requirements

- macOS 14+
- Xcode command line tools / Swift toolchain
- Homebrew `cmake` for building `whisper.cpp`
- Microphone permission
- Accessibility permission for auto-paste

## Setup

```bash
./script/setup_whisper_cpp.sh
```

This clones/builds `whisper.cpp` under `external/whisper.cpp` and downloads Whisper Large V3 to:

```text
Models/ggml-large-v3.bin
```

The model is about 2.9 GiB and is intentionally not committed to Git.

## Run

```bash
./script/build_and_run.sh
```

The app runs as a menu bar app. Default hotkey:

```text
Option-Space
```

Press once to start recording, press again to stop and transcribe.

## Notes

- The app uses `whisper-cli -ng` by default because the first Large V3 smoke test on this Mac failed with a Metal allocation error.
- CPU/Accelerate transcription is verified and works offline.
- Auto-paste failures do not discard the transcript; text remains in the clipboard.
