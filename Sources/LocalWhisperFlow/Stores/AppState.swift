import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: TranscriptionStatus = .idle
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastError: String?

    private let settings: SettingsStore
    private let audioRecorder = AudioRecorderService()
    private let whisperService = WhisperService()
    private let clipboardService = ClipboardService()
    private let pasteService = PasteService()
    private let hotkeyService = HotkeyService()

    init(settings: SettingsStore) {
        self.settings = settings
        registerHotkey()
    }

    func toggleRecording() {
        guard status.canToggleRecording else { return }

        if status == .recording {
            Task { await stopAndTranscribe() }
        } else {
            Task { await startRecording() }
        }
    }

    func registerHotkey() {
        do {
            try hotkeyService.register(
                keyCode: UInt32(settings.hotkeyKeyCode),
                modifiers: UInt32(settings.hotkeyModifiers)
            ) { [weak self] in
                Task { @MainActor in
                    self?.toggleRecording()
                }
            }
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
        }
    }

    func requestAccessibilityPermission() {
        _ = pasteService.requestAccessibilityPermission()
    }

    func hasAccessibilityPermission() -> Bool {
        pasteService.hasAccessibilityPermission()
    }

    private func startRecording() async {
        do {
            lastError = nil
            lastTranscript = ""
            _ = try await audioRecorder.startRecording()
            status = .recording
        } catch {
            fail(error)
        }
    }

    private func stopAndTranscribe() async {
        do {
            let audioURL = try audioRecorder.stopRecording()
            status = .transcribing

            let transcript = try await whisperService.transcribe(
                audioURL: audioURL,
                binaryPath: settings.whisperBinaryPath,
                modelPath: settings.modelPath,
                language: settings.language
            )

            lastTranscript = transcript
            clipboardService.copy(transcript)

            if settings.autoPaste {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try pasteService.paste()
                } catch {
                    lastError = "Copied to clipboard. Paste failed: \(error.localizedDescription)"
                }
            }

            status = .completed
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        lastError = message
        status = .failed(message)
    }
}
