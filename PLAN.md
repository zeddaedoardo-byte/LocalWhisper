# PLAN.md - LocalWhisperFlow

## Stato Corrente
*Aggiornato: 2026-05-02*

**Cosa e attivo ora:** MVP app menu bar locale con Whisper Large V3 e Control hold push-to-talk, ora sotto iCloud Drive.
**Blocchi:** test hotkey, microfono e auto-paste richiedono interazione utente/macOS permissions.
**Prossima cosa da fare:** concedere permessi e provare Control hold in una chat/test editor.

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
- [ ] Testare trascrizione end-to-end da microfono.

### Fase 2 - Qualita UX [PIANIFICATA]
- [ ] Migliorare feedback durante registrazione/trascrizione.
- [ ] Aggiungere gestione hotkey piu ergonomica.
- [ ] Migliorare diagnostica permessi.

### Fase 3 - Performance [PIANIFICATA]
- [ ] Valutare Core ML encoder per Apple Silicon.
- [ ] Valutare VAD/chunking.
- [ ] Valutare streaming o quasi realtime.

## Decisioni rimandate
- Core ML/Metal: rimandato per evitare di complicare il primo MVP; la smoke test Metal ha fallito su allocazione buffer, CPU/Accelerate funziona.
- Streaming realtime: rimandato fino a quando record/transcribe/paste e stabile.

## Fuori scope
- API cloud STT.
- Diarizzazione.
- Editing avanzato del testo trascritto.
