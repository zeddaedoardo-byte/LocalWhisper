# CLAUDE.md - LocalWhisperFlow

## Stack e convenzioni
- macOS app nativa con SwiftPM, SwiftUI, AppKit dove serve, AVFoundation per audio.
- Motore STT esterno: `whisper.cpp` con server persistente `whisper-server` (HTTP localhost:18642). `whisper-cli` resta come binario di riferimento per i path nelle settings.
- Modello default: Whisper Large V3 ggml in `~/Library/Application Support/LocalWhisperFlow/Models/ggml-large-v3.bin`. Il modello NON deve stare in iCloud Drive.
- Codice e commenti in inglese.

## Comandi principali
```bash
# Build e avvio app
./script/build_and_run.sh

# Build, download whisper.cpp e download modello Large V3
./script/setup_whisper_cpp.sh

# Solo build Swift
swift build --scratch-path /private/tmp/local-whisperflow-swiftpm-build

# Test
swift test --scratch-path /private/tmp/local-whisperflow-swiftpm-build
```

## Regole specifiche del progetto
- Non integrare API cloud per STT: il prodotto deve restare locale/offline.
- Non sostituire Large V3 con Turbo senza richiesta esplicita.
- Il flusso MVP resta Control hold push-to-talk -> transcribe -> clipboard/paste. Streaming realtime e VAD sono fase successiva.
- Control push-to-talk usa un `CGEvent` tap globale; non tornare a `NSEvent.addGlobalMonitorForEvents` per modifier-only globali senza una verifica reale.
- Non usare la `.build` dentro iCloud Drive per SwiftPM; usa `--scratch-path /private/tmp/local-whisperflow-swiftpm-build`.
- Non tracciare modelli `.bin` o build di `external/whisper.cpp` in Git.
- whisper.cpp va sempre buildato STATICO (`-DBUILD_SHARED_LIBS=OFF`) con Metal+Accelerate. Build dinamiche embeddano rpath assoluti che si rompono se la cartella si sposta.
- Non spostare il modello `ggml-large-v3.bin` dentro iCloud Drive: il lazy-load fa esplodere il cold start (200+ s).
- Quando si fa fork di un child process con `Process`+`Pipe`, drenare SEMPRE anche stdout (no-op handler), non solo stderr. Senza drain il child blocca quando il pipe buffer si riempie.
- Cleanup di child process: usare signal handler (SIGTERM/SIGINT/SIGHUP) + `atexit`, non solo `applicationWillTerminate` (non parte su SIGTERM diretto).

## Credenziali e configurazione
- Nessuna credenziale prevista.
- I path di `whisper-cli` e modello sono configurabili dalle Settings dell'app.
