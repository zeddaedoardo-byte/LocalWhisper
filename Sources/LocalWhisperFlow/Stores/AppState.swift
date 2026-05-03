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
    private var micSettingCancellable: AnyCancellable?
    private var triggerSettingCancellable: AnyCancellable?
    private var presetSettingCancellable: AnyCancellable?
    private var modelSettingCancellable: AnyCancellable?
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
        audioRecorder.preferredDeviceUID = settings.preferredMicUID.isEmpty ? nil : settings.preferredMicUID
        PushToTalkService.setTrigger(AppState.resolveTrigger(settings))
        observeAudioLevel()
        observeMicSetting()
        observeTriggerSetting()
        observePresetSetting()
        observeModelSetting()
        refreshAccessibilityStatus()
        startPushToTalk()
        scheduleWarmup()
        startAccessibilityPolling()

        Task { [weak audioRecorder] in
            await audioRecorder?.prewarm()
        }
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
        hasAccessibility = pasteService.hasAccessibilityPermission()
    }

    func scheduleWarmup() {
        warmupTask?.cancel()
        isServerReady = false
        let cliPath = settings.whisperBinaryPath
        let modelPath = settings.modelPath
        let params = currentDecodingParams
        isWarmingUp = true
        warmupTask = Task { [weak self] in
            do {
                try await self?.whisperService.warmup(cliBinaryPath: cliPath, modelPath: modelPath, params: params)
                await MainActor.run {
                    guard let self else { return }
                    self.isWarmingUp = false
                    self.isServerReady = true
                }
            } catch {
                await MainActor.run {
                    self?.isWarmingUp = false
                    self?.isServerReady = false
                    self?.lastError = "Warmup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var currentDecodingParams: WhisperServerWorker.DecodingParams {
        let preset = settings.performancePreset
        return .init(
            beamSize: preset.beamSize,
            bestOf: preset.bestOf,
            audioContext: preset.audioContext
        )
    }

    func shutdown() async {
        warmupTask?.cancel()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        pushToTalkService.stop()
        await whisperService.shutdown()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        clipboardService.copy(lastTranscript)
    }

    func runMicLevelTest(seconds: TimeInterval = 1.5) async -> Float {
        do {
            return try await audioRecorder.quickLevelTest(seconds: seconds)
        } catch {
            return -160
        }
    }

    private func observeAudioLevel() {
        levelCancellable = audioRecorder.$levelDB
            .receive(on: RunLoop.main)
            .sink { [weak self] db in
                self?.hudController.update(levelDB: db)
            }
    }

    private func observeMicSetting() {
        micSettingCancellable = settings.$preferredMicUID
            .receive(on: RunLoop.main)
            .sink { [weak self] uid in
                self?.audioRecorder.preferredDeviceUID = uid.isEmpty ? nil : uid
            }
    }

    private func observePresetSetting() {
        presetSettingCancellable = settings.$performancePresetID
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleWarmup()
            }
    }

    private func observeModelSetting() {
        modelSettingCancellable = settings.$modelPath
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleWarmup()
            }
    }

    private func observeTriggerSetting() {
        let updateTrigger: () -> Void = { [weak self] in
            guard let self else { return }
            PushToTalkService.setTrigger(AppState.resolveTrigger(self.settings))
        }
        triggerSettingCancellable = Publishers.MergeMany(
            settings.$pushToTalkTriggerID.map { _ in () }.eraseToAnyPublisher(),
            settings.$customTriggerKeycode.map { _ in () }.eraseToAnyPublisher(),
            settings.$customTriggerFlags.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { _ in updateTrigger() }
    }

    static func resolveTrigger(_ settings: SettingsStore) -> PushToTalkTrigger {
        if settings.pushToTalkTriggerID == "custom",
           settings.customTriggerKeycode >= 0,
           settings.customTriggerFlags != 0 {
            let label = settings.customTriggerLabel.isEmpty
                ? PushToTalkTrigger.describe(keycode: settings.customTriggerKeycode,
                                             flags: settings.customTriggerFlags)
                : settings.customTriggerLabel
            return PushToTalkTrigger.make(
                id: "custom",
                label: label,
                keycode: settings.customTriggerKeycode,
                flags: settings.customTriggerFlags
            )
        }
        return PushToTalkTrigger.byID(settings.pushToTalkTriggerID)
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
                    }
                }
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
            hudController.update(state: .recording)
        } catch {
            fail(error)
        }
    }

    private func stopAndTranscribe() async {
        do {
            let audioURL = try audioRecorder.stopRecording()
            status = .transcribing
            hudController.update(state: .transcribing)

            let transcript = try await whisperService.transcribe(
                audioURL: audioURL,
                binaryPath: settings.whisperBinaryPath,
                modelPath: settings.modelPath,
                language: settings.language,
                params: currentDecodingParams
            )

            lastTranscript = transcript
            clipboardService.copy(transcript)

            var pasteWarning: String?
            if settings.autoPaste {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try pasteService.paste()
                } catch {
                    pasteWarning = "Copiato negli appunti. Paste fallito: \(error.localizedDescription)"
                    lastError = pasteWarning
                }
            }

            isServerReady = true
            status = .completed
            let preview = String(transcript.prefix(72))
            if let pasteWarning {
                hudController.update(state: .error(pasteWarning))
            } else {
                hudController.update(state: .completed(preview))
            }
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        lastError = message
        status = .failed(message)
        hudController.update(state: .error(message))
    }
}
