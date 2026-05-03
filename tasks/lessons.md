# Lessons - LocalWhisper

- 2026-05-02: New projects requested by the user must be placed under `~/Library/Mobile Documents/com~apple~CloudDocs/Progetti` unless explicitly told otherwise. Do not default to the home root for durable project directories.
- 2026-05-02: When the user says continuous key press / push-to-talk, implement hold-to-record and release-to-transcribe, not a toggle shortcut.
- 2026-05-02: SwiftPM `.build` inside iCloud Drive can be modified by sync during builds. Use a `/private/tmp` scratch path for SwiftPM artifacts.
- 2026-05-02: Modifier-only global shortcuts on macOS should use a `CGEvent` tap and explicit press/release state. `NSEvent.addGlobalMonitorForEvents` is too weak for this push-to-talk case.
