# ORIENT.md - LocalWhisperFlow

*Cosa devo sapere per mettermi a lavorare su questo dopo due settimane di assenza?*

## Cos'e questo progetto
LocalWhisperFlow e una piccola app macOS locale stile WhisperFlow: una hotkey globale avvia e ferma la registrazione, l'audio viene trascritto offline con Whisper Large V3 via `whisper.cpp`, poi il testo viene copiato negli appunti e, se abilitato, incollato nell'app attiva. Il progetto vive sotto iCloud Drive in `/Users/edoardozedda/Library/Mobile Documents/com~apple~CloudDocs/Progetti/LocalWhisperFlow`.

## Modello mentale del codebase
La UI SwiftUI e solo un controllo sottile sopra servizi platform separati. `AppState` orchestra lo stato record/transcribe/paste. `AudioRecorderService` produce un WAV 16 kHz mono. `WhisperService` invoca `whisper-cli` come processo esterno. `ClipboardService` e `PasteService` gestiscono output. `HotkeyService` usa Carbon per la hotkey globale.

## Operazioni piu comuni
- **Avviare l'app**: `./script/build_and_run.sh`
- **Preparare whisper.cpp e Large V3**: `./script/setup_whisper_cpp.sh`
- **Repo locale**: lavorare sempre dalla cartella iCloud Drive del progetto.
- **Cambiare modello/binario**: apri Settings dall'icona menu bar e aggiorna i path.
- **Debug permessi**: controlla Microfono e Accessibility in System Settings.

## Stranezze note
- L'auto-paste richiede permesso Accessibility. Senza permesso, la trascrizione resta comunque in clipboard.
- Il modello Large V3 pesa circa 2.9 GiB, quindi il primo setup puo richiedere tempo.
- L'app e menu-bar-only e usa activation policy `.accessory`, quindi non appare nel Dock.
- Il backend Metal ha fallito nella prima smoke test Large V3 su questo Mac; l'app usa `whisper-cli -ng` per affidabilita.

## Link chiave
- whisper.cpp: https://github.com/ggerganov/whisper.cpp
