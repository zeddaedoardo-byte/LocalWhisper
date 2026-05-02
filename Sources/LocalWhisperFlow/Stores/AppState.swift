import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: TranscriptionStatus = .idle
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var isWarmingUp = false
    @Published private(set) var isServerReady = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var tapEventsReceived: Int = 0
    @Published private(set) var lastTapFlags: UInt64 = 0
    @Published private(set) var lastTapKeycode: Int = -1

    let hudController = RecordingHUDController()

    private let settings: SettingsStore
    private let audioRecorder = AudioRecorderService()
    private let whisperService = WhisperService()
    private let clipboardService = ClipboardService()
    private let pasteService = PasteService()
    private let pushToTalkService = PushToTalkService()
    private var isPushToTalkHeld = false
    private var isStartingPushToTalkRecording = false
    private var warmupTask: Task<Void, Never>?
    private var levelCancellable: AnyCancellable?
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
        audioRecorder.preferredDeviceUID = settings.preferredMicUID.isEmpty ? nil : settings.preferredMicUID
        PushToTalkService.setTrigger(PushToTalkTrigger.byID(settings.pushToTalkTriggerID))
        observeAudioLevel()
        observeMicSetting()
        observeTriggerSetting()
        hudController.update(state: .warmingUp, hint: "Booting Whisper Large V3...")
        refreshAccessibilityStatus()
        startPushToTalk()
        scheduleWarmup()
        startAccessibilityPolling()
    }

    func toggleRecording() {
        guard status.canToggleRecording else { return }

        if status == .recording {
            Task { await stopAndTranscribe() }
        } else {
            Task { await startRecording() }
        }
    }

    func startPushToTalk() {
        do {
            try pushToTalkService.start { [weak self] in
                Task { @MainActor in
                    self?.beginPushToTalkRecording()
                }
            } onRelease: { [weak self] in
                Task { @MainActor in
                    self?.endPushToTalkRecording()
                }
            }
        } catch {
            lastError = error.localizedDescription
            hudController.update(state: .error("Accessibility needed"),
                                 hint: "Enable in System Settings to use fn hold.")
        }
    }

    private func beginPushToTalkRecording() {
        guard status != .recording,
              status.canToggleRecording,
              !isStartingPushToTalkRecording else { return }

        isPushToTalkHeld = true
        isStartingPushToTalkRecording = true

        Task { @MainActor in
            await startRecording()
            isStartingPushToTalkRecording = false

            if !isPushToTalkHeld, status == .recording {
                await stopAndTranscribe()
            }
        }
    }

    private func endPushToTalkRecording() {
        guard isPushToTalkHeld else { return }
        isPushToTalkHeld = false

        if status == .recording {
            Task { await stopAndTranscribe() }
        }
    }

    func resetPushToTalk() {
        pushToTalkService.stop()
        startPushToTalk()
        refreshAccessibilityStatus()
    }

    func requestAccessibilityPermission() {
        _ = pasteService.requestAccessibilityPermission()
        refreshAccessibilityStatus()
    }

    func hasAccessibilityPermission() -> Bool {
        pasteService.hasAccessibilityPermission()
    }

    func refreshAccessibilityStatus() {
        let granted = pasteService.hasAccessibilityPermission()
        hasAccessibility = granted
        if !granted {
            hudController.update(state: .error("Accessibility needed"),
                                 hint: "System Settings → Accessibility → enable LocalWhisperFlow")
        }
    }

    func scheduleWarmup() {
        warmupTask?.cancel()
        isServerReady = false
        let cliPath = settings.whisperBinaryPath
        let modelPath = settings.modelPath
        isWarmingUp = true
        hudController.update(state: .warmingUp, hint: "Loading Whisper Large V3")
        warmupTask = Task { [weak self] in
            do {
                try await self?.whisperService.warmup(cliBinaryPath: cliPath, modelPath: modelPath)
                await MainActor.run {
                    guard let self else { return }
                    self.isWarmingUp = false
                    self.isServerReady = true
                    let hint = self.hasAccessibility
                        ? "Hold fn to dictate"
                        : "Grant Accessibility to enable Control hotkey"
                    self.hudController.update(state: .ready, hint: hint)
                }
            } catch {
                await MainActor.run {
                    self?.isWarmingUp = false
                    self?.isServerReady = false
                    self?.lastError = "Warmup failed: \(error.localizedDescription)"
                    self?.hudController.update(state: .error("Warmup failed"),
                                               hint: error.localizedDescription)
                }
            }
        }
    }

    func shutdown() async {
        warmupTask?.cancel()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        pushToTalkService.stop()
        await whisperService.shutdown()
    }

    private func observeAudioLevel() {
        levelCancellable = audioRecorder.$levelDB
            .receive(on: RunLoop.main)
            .sink { [weak self] db in
                self?.hudController.update(levelDB: db)
            }
    }

    private var micSettingCancellable: AnyCancellable?
    private var triggerSettingCancellable: AnyCancellable?

    private func observeMicSetting() {
        micSettingCancellable = settings.$preferredMicUID
            .receive(on: RunLoop.main)
            .sink { [weak self] uid in
                self?.audioRecorder.preferredDeviceUID = uid.isEmpty ? nil : uid
            }
    }

    private func observeTriggerSetting() {
        triggerSettingCancellable = settings.$pushToTalkTriggerID
            .receive(on: RunLoop.main)
            .sink { id in
                PushToTalkService.setTrigger(PushToTalkTrigger.byID(id))
            }
    }

    func runMicLevelTest(seconds: TimeInterval = 1.5) async -> Float {
        do {
            return try await audioRecorder.quickLevelTest(seconds: seconds)
        } catch {
            return -160
        }
    }

    private func startAccessibilityPolling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let granted = self.pasteService.hasAccessibilityPermission()
                if granted != self.hasAccessibility {
                    self.hasAccessibility = granted
                    if granted {
                        self.resetPushToTalk()
                        if self.isServerReady {
                            self.hudController.update(state: .ready, hint: "Hold fn to dictate")
                        }
                    } else {
                        self.hudController.update(state: .error("Accessibility needed"),
                                                  hint: "System Settings → Accessibility → enable LocalWhisperFlow")
                    }
                }
                self.tapEventsReceived = PushToTalkService.currentEventCount()
                self.lastTapFlags = PushToTalkService.currentLastFlagsRaw()
                self.lastTapKeycode = PushToTalkService.currentLastKeycode()
                let diag = String(format: "events:%d  kc:%d  flags:0x%llx",
                                  self.tapEventsReceived,
                                  self.lastTapKeycode,
                                  self.lastTapFlags)
                self.hudController.update(diagnostic: diag)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPollTimer = timer
    }

    private func startRecording() async {
        do {
            lastError = nil
            lastTranscript = ""
            _ = try await audioRecorder.startRecording()
            status = .recording
            hudController.update(state: .recording, hint: "Speak — release Control to transcribe")
        } catch {
            fail(error)
        }
    }

    private func stopAndTranscribe() async {
        do {
            let audioURL = try audioRecorder.stopRecording()
            status = .transcribing
            hudController.update(state: .transcribing, hint: "Whisper Large V3")

            let transcript = try await whisperService.transcribe(
                audioURL: audioURL,
                binaryPath: settings.whisperBinaryPath,
                modelPath: settings.modelPath,
                language: settings.language
            )

            lastTranscript = transcript
            clipboardService.copy(transcript)

            var pasteWarning: String?
            if settings.autoPaste {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try pasteService.paste()
                } catch {
                    pasteWarning = "Copied to clipboard. Paste failed: \(error.localizedDescription)"
                    lastError = pasteWarning
                }
            }

            isServerReady = true
            status = .completed
            let preview = transcript.prefix(40)
            hudController.update(state: .completed,
                                 hint: pasteWarning ?? String(preview))
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        lastError = message
        status = .failed(message)
        hudController.update(state: .error("Error"), hint: message)
    }
}
