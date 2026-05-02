# PLAN.md - LocalWhisperFlow

## Stato Corrente
*Aggiornato: 2026-05-02*

**Cosa e attivo ora:** MVP app menu bar locale con Whisper Large V3 e Control hold push-to-talk, ora sotto iCloud Drive.
**Blocchi:** test hotkey, microfono e auto-paste richiedono interazione utente/macOS permissions.
**Prossima cosa da fare:** ottimizzare per Apple Silicon, poi concedere permessi e provare Control hold in una chat/test editor.

---

## Obiettivo
Replicare il flusso essenziale di WhisperFlow in locale: Control hold push-to-talk, registrazione microfono, trascrizione offline con Whisper Large V3, copia in clipboard e paste nell'app attiva.

## Criteri di successo
- [ ] Control hold avvia la registrazione e il rilascio ferma/trascrive anche quando l'app non e in foreground.
- [ ] L'app chiede permesso microfono.
- [ ] L'audio viene salvato come WAV 16 kHz mono compatibile con `whisper-cli`.
- [ ] `whisper.cpp` trascrive con `Models/ggml-large-v3.bin`.
- [ ] Il testo viene copiato in clipboard.
- [ ] Se Accessibility e autorizzato, il testo viene incollato nell'app attiva.
- [ ] Errori per modello/binario/permessi mancanti sono leggibili.

## Fasi

### Fase 1 - MVP locale [IN CORSO]
- [x] Definire piano e assunzioni.
- [x] Creare scaffold SwiftPM macOS.
- [x] Implementare servizi base.
- [x] Verificare build Swift.
- [x] Buildare `whisper.cpp`.
- [x] Scaricare Whisper Large V3 ggml.
- [x] Testare trascrizione Large V3 su sample WAV.
- [x] Verificare lancio bundle app.
- [x] Spostare progetto sotto iCloud Drive.
- [x] Creare commit locale iniziale su `main`.
- [x] Pubblicare sorgenti su GitHub.
- [x] Cambiare default da Option-Space toggle a Control hold push-to-talk.
- [x] Fixare Control push-to-talk con `CGEvent` tap globale e test state machine.
- [ ] Testare trascrizione end-to-end da microfono.

### Fase 2 - Qualita UX [PIANIFICATA]
- [ ] Migliorare feedback durante registrazione/trascrizione.
- [ ] Aggiungere gestione hotkey piu ergonomica.
- [ ] Migliorare diagnostica permessi.

### Fase 3 - Performance [PIANIFICATA]
**Fondamentale:** l'app deve essere ottimizzata per Apple Silicon prima di considerare il prodotto usabile come alternativa a WhisperFlow. L'MVP CPU/Accelerate serve solo come baseline stabile.

- [ ] Riprodurre e diagnosticare il fallimento Metal Large V3 (`ggml_metal_buffer_init: failed to allocate buffer`).
- [ ] Rimuovere il fallback forzato `-ng` quando Metal/Core ML e stabile.
- [ ] Buildare `whisper.cpp` con supporto Apple Silicon completo: Metal e Core ML (`WHISPER_COREML=1`).
- [ ] Generare o scaricare l'encoder Core ML per Whisper Large V3 e documentare il path atteso.
- [ ] Misurare tempi baseline CPU/Accelerate vs Metal/Core ML su sample e frase dettata reale.
- [ ] Ridurre il costo di cold start: evitare di ricaricare 3 GB di modello a ogni dettatura, tramite worker persistente o integrazione diretta della libreria.
- [ ] Valutare footprint di Large V3 pieno su questo Mac; se resta troppo lento, proporre esplicitamente tradeoff con `large-v3-q5_0` senza cambiare default in autonomia.
- [ ] Valutare VAD/chunking dopo l'ottimizzazione Apple Silicon.
- [ ] Valutare streaming o quasi realtime dopo worker persistente/Core ML.

## Decisioni rimandate
- Core ML/Metal: non e opzionale; e rimandato solo dopo il fix del push-to-talk. La smoke test Metal ha fallito su allocazione buffer, CPU/Accelerate funziona come baseline.
- Streaming realtime: rimandato fino a quando record/transcribe/paste e stabile.

## Fuori scope
- API cloud STT.
- Diarizzazione.
- Editing avanzato del testo trascritto.
