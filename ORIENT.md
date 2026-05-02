# ORIENT.md - LocalWhisperFlow

*Cosa devo sapere per mettermi a lavorare su questo dopo due settimane di assenza?*

## Cos'e questo progetto
LocalWhisperFlow e una piccola app macOS locale stile WhisperFlow: tieni premuto Control per registrare, rilasci Control per trascrivere offline con Whisper Large V3 via `whisper.cpp`, poi il testo viene copiato negli appunti e, se abilitato, incollato nell'app attiva. Il progetto vive sotto iCloud Drive in `/Users/edoardozedda/Library/Mobile Documents/com~apple~CloudDocs/Progetti/LocalWhisperFlow`.

## Modello mentale del codebase
La UI SwiftUI e solo un controllo sottile sopra servizi platform separati. `AppState` orchestra lo stato record/transcribe/paste. `AudioRecorderService` produce un WAV 16 kHz mono. `WhisperService` invoca `whisper-cli` come processo esterno. `ClipboardService` e `PasteService` gestiscono output. `PushToTalkService` usa un `CGEvent` tap globale per intercettare press/release di Control.

## Operazioni piu comuni
- **Avviare l'app**: `./script/build_and_run.sh`
- **Eseguire i test**: `swift test --scratch-path /private/tmp/local-whisperflow-swiftpm-build`
- **Preparare whisper.cpp e Large V3**: `./script/setup_whisper_cpp.sh`
- **Repo locale**: lavorare sempre dalla cartella iCloud Drive del progetto.
- **Cambiare modello/binario**: apri Settings dall'icona menu bar e aggiorna i path.
- **Debug permessi**: controlla Microfono e Accessibility in System Settings. Control push-to-talk globale richiede Accessibility.

## Stranezze note
- L'auto-paste richiede permesso Accessibility. Senza permesso, la trascrizione resta comunque in clipboard.
- Control push-to-talk globale richiede permesso Accessibility; il pulsante manuale nel menu resta come fallback.
- La logica press/release ha una state machine testata in `PushToTalkStateMachineTests`.
- Il modello Large V3 pesa circa 2.9 GiB, quindi il primo setup puo richiedere tempo.
- L'app e menu-bar-only e usa activation policy `.accessory`, quindi non appare nel Dock.
- Il backend Metal ha fallito nella prima smoke test Large V3 su questo Mac; l'app usa `whisper-cli -ng` per affidabilita.
- SwiftPM deve usare scratch path in `/private/tmp` per evitare che iCloud sincronizzi object file durante la build.

## Link chiave
- Repository: https://github.com/zeddaedoardo-byte/LocalWhisperFlow
- whisper.cpp: https://github.com/ggerganov/whisper.cpp
