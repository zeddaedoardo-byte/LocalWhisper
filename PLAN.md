# PLAN.md - LocalWhisperFlow

## Stato Corrente
*Aggiornato: 2026-05-02*

**Cosa e attivo ora:** MVP funzionante end-to-end. App menu bar locale, whisper-server persistente con Metal + Accelerate, modello Large V3 in `~/Library/Application Support/LocalWhisperFlow/Models`, Control hold push-to-talk, auto-paste opzionale.
**Blocchi:** test di registrazione microfono dal vivo richiede interazione utente e permessi (Microphone + Accessibility).
**Prossima cosa da fare:** verifica live record/paste in chat reale, poi feedback visivo su warmup/registrazione e gestione errori UX.

---

## Obiettivo
Replicare il flusso essenziale di WhisperFlow in locale: Control hold push-to-talk, registrazione microfono, trascrizione offline con Whisper Large V3 su Apple Silicon (Metal), copia in clipboard e paste nell'app attiva.

## Criteri di successo
- [x] Control hold avvia la registrazione e il rilascio ferma/trascrive anche quando l'app non e in foreground.
- [x] L'app chiede permesso microfono.
- [x] L'audio viene salvato come WAV 16 kHz mono compatibile con whisper.cpp.
- [x] whisper.cpp (via whisper-server persistente) trascrive con `Models/ggml-large-v3.bin` su Metal.
- [x] Il testo viene copiato in clipboard.
- [x] Se Accessibility e autorizzato, il testo viene incollato nell'app attiva.
- [x] Errori per modello/binario/permessi mancanti sono leggibili.

## Fasi

### Fase 1 - MVP locale [COMPLETATA]
- [x] Definire piano e assunzioni.
- [x] Creare scaffold SwiftPM macOS.
- [x] Implementare servizi base.
- [x] Verificare build Swift.
- [x] Buildare whisper.cpp con Metal + Accelerate (build statica per evitare rpath rotti dopo move).
- [x] Scaricare Whisper Large V3 ggml.
- [x] Spostare il modello fuori da iCloud Drive in Application Support.
- [x] Implementare `WhisperServerWorker` persistente (HTTP localhost:18642).
- [x] Warmup automatico del modello al lancio app.
- [x] Cleanup server in `applicationWillTerminate` + signal handler (SIGTERM/SIGINT/SIGHUP) + atexit.
- [x] Migrazione UserDefaults: reset path stale che puntano a posizione pre-iCloud.
- [x] Smoke test end-to-end con sample WAV: trascrizione corretta in ~2.6 s su steady state.
- [ ] Test microfono reale (richiede utente).

### Fase 2 - Qualita UX [PIANIFICATA]
- [ ] Indicatore visivo di warmup (modello in load) e di stato server.
- [ ] Feedback visivo durante registrazione e trascrizione.
- [ ] Diagnostica permessi piu chiara nel menu.
- [ ] Hotkey configurabile (oltre a Control hold).

### Fase 3 - Performance [PIANIFICATA]
- [ ] Provare Core ML encoder per Large V3 (richiede generazione encoder + WHISPER_COREML=1).
- [ ] Misurare e ridurre cold start del server (oggi ~5-10 s su SSD locale, ~40 s da rsync fresh).
- [ ] Valutare `large-v3-q5_0` come opzione esplicita per ridurre footprint.
- [ ] Valutare VAD/chunking e streaming dopo Core ML.

## Decisioni rimandate
- Core ML encoder: rimandato a Fase 3 dopo verifica live del flusso.
- Streaming realtime: rimandato fino a quando Core ML e UX sono stabili.

## Fuori scope
- API cloud STT.
- Diarizzazione.
- Editing avanzato del testo trascritto.
