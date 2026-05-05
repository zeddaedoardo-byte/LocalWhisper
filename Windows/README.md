# LocalWhisper for Windows

This is the Windows port of LocalWhisper. It is intentionally kept under
`Windows/` so the original macOS SwiftUI app remains untouched.

The product behavior mirrors the Mac app:

- tray-only desktop app
- hold-to-talk global hotkey
- WASAPI microphone capture
- 16 kHz mono WAV handoff to `whisper.cpp`
- persistent `whisper-server.exe` on `127.0.0.1:18642`
- offline transcription with Whisper Large V3 by default
- clipboard copy and optional `Ctrl+V` auto-paste

## Requirements

- Windows 10 19041 or newer, Windows 11 recommended
- .NET 8 SDK
- Git
- CMake
- Visual Studio 2022 Build Tools with the C++ desktop workload

Optional acceleration depends on the machine:

- CPU baseline works everywhere but can be slow with Large V3.
- CUDA is the best path for NVIDIA machines.
- Vulkan is the most useful cross-vendor GPU path.
- OpenVINO can be evaluated for Intel systems.

## Build `whisper.cpp`

From this `Windows/` directory in PowerShell:

```powershell
.\scripts\build_whisper_cpp.ps1 -Backend cpu
```

For GPU builds:

```powershell
.\scripts\build_whisper_cpp.ps1 -Backend cuda
.\scripts\build_whisper_cpp.ps1 -Backend vulkan
```

The script clones `whisper.cpp`, builds it statically, and installs
`whisper-cli.exe` plus `whisper-server.exe` into:

```text
%LOCALAPPDATA%\LocalWhisper\bin
```

## Build the app

```powershell
.\scripts\build_windows.ps1
```

The published app lands in:

```text
Windows\artifacts\LocalWhisper-win-x64
```

## First run

Launch `LocalWhisper.exe`. Open Settings from the tray icon and either:

- download Large V3 from the Whisper tab, or
- select an existing `ggml-large-v3.bin`.

The default model location is:

```text
%LOCALAPPDATA%\LocalWhisper\Models\ggml-large-v3.bin
```

Do not put the model under OneDrive or another synced folder. Large V3 is read
heavily during cold start and should live on a local disk.

## Windows-specific notes

- Windows does not expose the Mac `fn` key to normal apps, so the default
  trigger is Left Ctrl.
- Auto-paste uses `SendInput` for `Ctrl+V`. Windows can block this across
  elevated/UAC boundaries; the transcript is still copied to the clipboard.
- The keyboard hook runs as a normal low-level hook, not a cloud service or
  remote component. Audio and transcription stay local.
- `whisper-cli.exe` is still used as the user-facing path because it identifies
  the folder containing `whisper-server.exe`, matching the macOS app convention.
