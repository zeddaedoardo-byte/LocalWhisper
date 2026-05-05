# MEMORY.md - LocalWhisper

## Decisioni architetturali
- [domain] 2026-05-02 Scelto whisper.cpp come motore locale invece di Python/faster-whisper per stabilita e distribuibilita.
- [domain] 2026-05-05 Default aggiornato a Whisper Large V3 Turbo per efficienza/latency. Path default modello: `~/Library/Application Support/LocalWhisper/Models/ggml-large-v3-turbo.bin`.
- [domain] 2026-05-02 Scelto MVP Control hold push-to-talk → transcribe → clipboard/paste. Streaming realtime, VAD e Core ML rimandati.
- [domain] 2026-05-02 Progetto vive sotto iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/Progetti/LocalWhisper`. Il MODELLO invece NON deve stare in iCloud (vedi gotcha sotto).
- [domain] 2026-05-02 Architettura runtime: `whisper-server` persistente come child process del bundle. App parla via HTTP `127.0.0.1:18642`. Modello caricato una sola volta al warmup; ogni dictation successiva ~2.6 s su M3 con Metal + Accelerate per audio 11 s.
- [domain] 2026-05-02 whisper.cpp viene buildato STATICO (`-DBUILD_SHARED_LIBS=OFF`) con `-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=Apple`. Eseguibili autocontenuti, non si rompono se la cartella viene spostata.

## Gotchas e comportamenti non ovvi
- [domain] iCloud Drive + modelli Whisper grandi = morte: il primo mmap del modello tagged iCloud puo richiedere molto (lazy load di pagine). Soluzione: tenere il modello in `~/Library/Application Support/LocalWhisper/Models/`.
- [domain] Build whisper.cpp NON statica = rpath assoluto al path della build. Se la cartella viene spostata, `whisper-cli` cerca `libwhisper.1.dylib` al vecchio path e crasha con `dyld: Library not loaded`. Build statica risolve.
- [domain] `Process` con `Pipe` su stdout NON drenata blocca il child quando il buffer pipe (~64 KB) si riempie. whisper-server scrive molto a stdout in init: bisogna installare un `readabilityHandler` no-op anche su stdout, oltre che su stderr.
- [domain] `applicationWillTerminate` non viene chiamato se il processo riceve SIGTERM diretto (es. `pkill`). Per cleanup server affidabile servono signal handler espliciti (SIGTERM/SIGINT/SIGHUP) + `atexit` come backstop.
- [domain] UserDefaults possono contenere path obsoleti da run precedenti (es. binario whisper a vecchia posizione pre-iCloud). `SettingsStore.init` deve verificare che il path stored sia ancora valido (FileManager) e ricadere sul default altrimenti, salvando il nuovo valore.
- [domain] macOS: Microfono richiede `NSMicrophoneUsageDescription` nel bundle `.app`. Il run script genera Info.plist esplicito.
- [domain] macOS: Auto-paste via eventi tastiera richiede Accessibility. Senza permesso il testo resta in clipboard.
- [domain] macOS: Control hold push-to-talk globale usa `CGEvent` tap `flagsChanged`, non `NSEvent.addGlobalMonitorForEvents`. Richiede Accessibility per funzionare fuori dall'app.
- [domain] UX: Un fallimento di auto-paste non deve marcare la trascrizione come fallita; mostra warning ma lascia stato `completed` e testo in clipboard.
- [domain] UX: La release di Control puo arrivare mentre `AVAudioRecorder` sta ancora partendo; `AppState` traccia `isPushToTalkHeld` e ferma/trascrive appena la registrazione diventa attiva.
- [domain] whisper.cpp: `whisper-cli`/`whisper-server` accettano WAV 16-bit. `AudioRecorderService` registra direttamente WAV PCM 16 kHz mono.
- [domain] SwiftPM: `.build` dentro iCloud Drive puo dare `input file was modified during the build`. Run script usa `/private/tmp/local-whisperflow-swiftpm-build`.
- [domain] iCloud Drive puo bloccare temporaneamente la lettura di un file appena scritto (race con sync). Se un Read/Edit fallisce con timeout, attendere qualche secondo e riprovare.

## Conoscenza procedurale
- [procedural] Setup locale: `./script/setup_whisper_cpp.sh` — clona whisper.cpp, build statica con Metal, scarica Large V3 Turbo in Application Support.
- [procedural] Build e run app: `./script/build_and_run.sh`. Modalita: `run` default, `--verify`, `--logs`, `--telemetry`, `--debug`.
- [procedural] Test: `swift test --scratch-path /private/tmp/local-whisperflow-swiftpm-build`.
- [procedural] Debug server: ping `curl http://127.0.0.1:18642/` per ready, POST multipart `/inference` con campo `file`, `language`, `response_format=text`.
- [procedural] Cleanup orfani server in dev: `pkill -f whisper-server`.
- [procedural] I build artifact e modelli sono ignorati da Git: `external/`, `.build/`, `dist/`, `Models/*.bin`.
- [procedural] GitHub non deve includere `Models/*.bin` (modelli Whisper grandi).

## Stato corrente (aggiornato ogni sessione)
- Ultima sessione: 2026-05-02
- Cosa e stato fatto: pipeline end-to-end resa funzionante. Rebuild whisper.cpp statico con Metal+Accelerate (fix rpath rotto dopo move iCloud). Modello spostato fuori iCloud in Application Support (fix lazy-load 200 s). Sostituito spawn-per-dictation con `WhisperServerWorker` persistente. Aggiunto warmup automatico. Aggiunti signal handler + atexit per cleanup server. Migrazione UserDefaults stale. Smoke test: ready 2-40 s, inference 2.6 s su 11 s audio.
- Blocchi aperti: verifica live con microfono reale + auto-paste in app concreta richiede l'utente.
