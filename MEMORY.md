# MEMORY.md - LocalWhisperFlow

## Decisioni architetturali
- [domain] 2026-05-02 Scelto `whisper.cpp` come motore locale invece di Python/faster-whisper per avere una app macOS piu stabile e distribuibile.
- [domain] 2026-05-02 Scelto Whisper Large V3, non Turbo, per privilegiare accuratezza. Il path modello default e `Models/ggml-large-v3.bin`.
- [domain] 2026-05-02 Scelto MVP record -> transcribe -> clipboard/paste. Streaming realtime, VAD e Core ML sono rimandati.
- [domain] 2026-05-02 Il progetto deve vivere sotto iCloud Drive: `/Users/edoardozedda/Library/Mobile Documents/com~apple~CloudDocs/Progetti/LocalWhisperFlow`.

## Gotchas e comportamenti non ovvi
- [domain] macOS: Microfono richiede `NSMicrophoneUsageDescription` nel bundle `.app`, quindi il run script genera un `Info.plist` esplicito.
- [domain] macOS: Auto-paste via eventi tastiera richiede Accessibility. Senza permesso il testo resta in clipboard.
- [domain] UX: Un fallimento di auto-paste non deve marcare la trascrizione come fallita; mostra warning ma lascia stato completed e testo in clipboard.
- [domain] whisper.cpp: `whisper-cli` richiede WAV 16-bit; `AudioRecorderService` registra direttamente WAV PCM 16 kHz mono.
- [domain] whisper.cpp: su questo Mac la smoke test Large V3 con Metal ha fallito con `ggml_metal_buffer_init: failed to allocate buffer`. L'MVP passa `-ng` a `whisper-cli` e usa CPU/Accelerate.

## Conoscenza procedurale
- [procedural] Setup locale: eseguire `./script/setup_whisper_cpp.sh`, poi `./script/build_and_run.sh`.
- [procedural] I build artifact e modelli sono ignorati da Git: `external/`, `.build/`, `dist/`, `Models/*.bin`.
- [procedural] GitHub non deve includere `Models/ggml-large-v3.bin` perche pesa circa 2.9 GiB e supera i limiti pratici di GitHub standard.

## Stato corrente (aggiornato ogni sessione)
- Ultima sessione: 2026-05-02
- Cosa e stato fatto: scaffold SwiftPM, servizi principali, run script, setup script, COMP iniziale, build Swift, build whisper.cpp, download Large V3, smoke test CPU/no-GPU, bundle app verificato con `./script/build_and_run.sh --verify`, progetto spostato interamente sotto iCloud Drive, commit locale iniziale creato su `main`.
- Blocchi aperti: GitHub CLI ha token invalido; push online bloccato finche non viene rifatto `gh auth login`.
