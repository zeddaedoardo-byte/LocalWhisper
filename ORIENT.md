# ORIENT.md - LocalWhisper

*Cosa devo sapere per mettermi a lavorare su questo dopo due settimane di assenza?*

## Cos'e questo progetto
LocalWhisper e una piccola app macOS locale stile WhisperFlow: tieni premuto Control per registrare, rilasci Control per trascrivere offline con Whisper Large V3 via `whisper.cpp` (Metal + Accelerate), poi il testo viene copiato negli appunti e, se abilitato, incollato nell'app attiva. Il sorgente vive sotto iCloud Drive in `/Users/edoardozedda/Library/Mobile Documents/com~apple~CloudDocs/Progetti/LocalWhisper`. Il modello Large V3 invece NON sta in iCloud: vive in `~/Library/Application Support/LocalWhisper/Models/`.

## Modello mentale del codebase
La UI SwiftUI e un controllo sottile sopra servizi platform separati. `AppState` orchestra lo stato record/transcribe/paste e possiede un `WhisperService` che a sua volta gestisce un `WhisperServerWorker` (actor). Il worker fa fork di `whisper-server` come child process al primo warmup e lo tiene vivo per l'intera vita dell'app. Le dictation diventano POST multipart su `127.0.0.1:18642/inference`. `AudioRecorderService` produce WAV PCM 16 kHz mono. `ClipboardService` e `PasteService` gestiscono output. `PushToTalkService` usa un `CGEvent` tap globale per intercettare press/release di Control. `AppDelegate` installa signal handler e cleanup hook per terminare ogni server registrato in caso di SIGTERM/SIGINT/SIGHUP o quit normale.

## Operazioni piu comuni
- **Avviare l'app**: `./script/build_and_run.sh`
- **Eseguire i test**: `swift test --scratch-path /private/tmp/local-whisperflow-swiftpm-build`
- **Preparare whisper.cpp e Large V3**: `./script/setup_whisper_cpp.sh`
- **Repo locale**: lavorare sempre dalla cartella iCloud Drive del progetto.
- **Cambiare modello/binario**: apri Settings dall'icona menu bar e aggiorna i path.
- **Debug permessi**: System Settings > Privacy > Microphone e Accessibility.
- **Debug server**: `curl http://127.0.0.1:18642/` per ready, oppure `pgrep -fl whisper-server`. Cleanup: `pkill -f whisper-server`.

## Stranezze note
- Build whisper.cpp deve essere STATICA (`BUILD_SHARED_LIBS=OFF`). Una build dinamica embedda rpath assoluti al path della build dir; spostando la cartella, gli eseguibili crashano con `dyld: Library not loaded`.
- Il modello Large V3 NON deve stare in iCloud Drive: il lazy-load di iCloud rende il primo mmap di un file 3 GB straordinariamente lento (200+ s). In Application Support cold start e ~5-10 s.
- `Process` con `Pipe` su stdout deve avere un drain (anche no-op): senza, il pipe buffer si riempie e il child blocca in `write`. whisper-server scrive molto a stdout in init.
- `applicationWillTerminate` NON parte su SIGTERM diretto (es. `pkill`). Servono signal handler espliciti se vuoi pulizia affidabile dei child.
- L'auto-paste richiede Accessibility. Senza permesso, la trascrizione resta in clipboard.
- Control push-to-talk globale richiede Accessibility; il pulsante manuale nel menu resta come fallback.
- Logica press/release ha state machine testata in `PushToTalkStateMachineTests`.
- L'app e menu-bar-only (activation policy `.accessory`), quindi non appare nel Dock.
- SwiftPM build path = `/private/tmp/local-whisperflow-swiftpm-build` (no iCloud sync race su object file).

## Link chiave
- Repository: https://github.com/zeddaedoardo-byte/LocalWhisper
- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Endpoint server in dev: `http://127.0.0.1:18642/inference`
