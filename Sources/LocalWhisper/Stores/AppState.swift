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
    @Published private(set) var lastFailedAudioURL: URL?

    let hudController = RecordingHUDController()

    private let settings: SettingsStore
    private let audioRecorder = AudioRecorderService()
    private let whisperService = WhisperService()
    private let clipboardService = ClipboardService()
    private let pasteService = PasteService()
    private let pushToTalkService = PushToTalkService()
    private let escapeMonitor = EscapeKeyMonitor()
    private var isPushToTalkHeld = false
    private var isStartingPushToTalkRecording = false
    private var warmupTask: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var lastAudioURL: URL?
    private var didAbort = false
    private var levelCancellable: AnyCancellable?
    private var micSettingCancellable: AnyCancellable?
    private var triggerSettingCancellable: AnyCancellable?
    private var presetSettingCancellable: AnyCancellable?
    private var modelSettingCancellable: AnyCancellable?
    private var soundSettingCancellable: AnyCancellable?
    private var launchSettingCancellable: AnyCancellable?
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
        audioRecorder.preferredDeviceUID = settings.preferredMicUID.isEmpty ? nil : settings.preferredMicUID
        PushToTalkService.setTrigger(AppState.resolveTrigger(settings))
        SoundService.shared.isEnabled = settings.playSounds
        applyLaunchAtLoginSetting()
        observeAudioLevel()
        observeMicSetting()
        observeTriggerSetting()
        observePresetSetting()
        observeModelSetting()
        observeSoundSetting()
        observeLaunchSetting()
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
            transcribeTask?.cancel()
            transcribeTask = Task { [weak self] in
                await self?.stopAndTranscribe()
            }
        }
    }

    func abortInProgress() {
        guard status == .recording || status == .transcribing else { return }

        didAbort = true
        SoundService.shared.playStopListening()

        if status == .recording {
            isPushToTalkHeld = false
            isStartingPushToTalkRecording = false
            if let url = try? audioRecorder.stopRecording() {
                try? FileManager.default.removeItem(at: url)
            }
            status = .idle
            lastError = nil
            hudController.update(state: .hidden)
            stopEscapeMonitor()
        } else {
            // .transcribing — cancel the inflight HTTP request AND kill the
            // whisper-server. Cancelling only the HTTP client does not stop
            // server-side inference once it has started; the server keeps
            // computing until completion. Forcing a shutdown of the worker
            // process is the only way to actually abort.
            transcribeTask?.cancel()
            transcribeTask = nil
            status = .idle
            lastError = nil
            hudController.update(state: .hidden)
            stopEscapeMonitor()
            let service = whisperService
            Task { [weak self] in
                await service.shutdown()
                await MainActor.run {
                    self?.scheduleWarmup()
                }
            }
        }
    }

    private func startEscapeMonitor() {
        guard !escapeMonitor.isActive else { return }
        escapeMonitor.start { [weak self] in
            self?.abortInProgress()
        }
    }

    private func stopEscapeMonitor() {
        escapeMonitor.stop()
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

    func clearLastFailedAudio() {
        if let url = lastFailedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        lastFailedAudioURL = nil
    }

    private func keepAsLastFailedAudio(_ source: URL) {
        let fm = FileManager.default
        let dir = ProjectPaths.applicationSupportRoot
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent("last-failed.wav")
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.moveItem(at: source, to: destination)
            lastFailedAudioURL = destination
        } catch {
            // Fall back to deleting if we can't move.
            try? fm.removeItem(at: source)
            lastFailedAudioURL = nil
        }
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

    private func observeSoundSetting() {
        soundSettingCancellable = settings.$playSounds
            .receive(on: RunLoop.main)
            .sink { enabled in
                SoundService.shared.isEnabled = enabled
            }
    }

    private func observeLaunchSetting() {
        launchSettingCancellable = settings.$launchAtLogin
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLaunchAtLoginSetting()
            }
    }

    private func applyLaunchAtLoginSetting() {
        let desired = settings.launchAtLogin
        let actual = LoginItemService.shared.setEnabled(desired)
        if !actual, desired {
            // Failed to register: reflect actual state back to settings to keep UI honest.
            settings.launchAtLogin = false
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
            didAbort = false
            _ = try await audioRecorder.startRecording()
            SoundService.shared.playStartListening()
            status = .recording
            hudController.update(state: .recording)
            startEscapeMonitor()
        } catch {
            fail(error)
        }
    }

    private func stopAndTranscribe() async {
        var pendingAudioURL: URL?
        var transcribeSucceeded = false
        defer {
            if let url = pendingAudioURL {
                if transcribeSucceeded {
                    try? FileManager.default.removeItem(at: url)
                } else if didAbort {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    keepAsLastFailedAudio(url)
                }
            }
        }
        do {
            let audioURL = try audioRecorder.stopRecording()
            pendingAudioURL = audioURL
            SoundService.shared.playStopListening()
            status = .transcribing
            hudController.update(state: .transcribing)
            startEscapeMonitor()

            let transcript = try await whisperService.transcribe(
                audioURL: audioURL,
                binaryPath: settings.whisperBinaryPath,
                modelPath: settings.modelPath,
                language: settings.language,
                params: currentDecodingParams
            )
            transcribeSucceeded = true

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
            stopEscapeMonitor()
            let preview = String(transcript.prefix(72))
            if let pasteWarning {
                hudController.update(state: .error(pasteWarning))
            } else {
                hudController.update(state: .completed(preview))
            }
        } catch {
            if didAbort {
                didAbort = false
                return
            }
            stopEscapeMonitor()
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
