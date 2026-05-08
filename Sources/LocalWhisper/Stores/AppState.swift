import AVFoundation
import AppKit
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
    private let llmRefiner = LLMRefinerService()
    private let clipboardService = ClipboardService()
    private let pasteService = PasteService()
    private let pushToTalkService = PushToTalkService()
    private let escapeMonitor = EscapeKeyMonitor()
    private let silenceWatchdog = SilenceWatchdog()
    private var isPushToTalkHeld = false
    private var isStartingPushToTalkRecording = false
    private enum PTTMode { case idle, hold, continuous }
    private var pttMode: PTTMode = .idle
    private var lockTriggerSettingCancellable: AnyCancellable?
    /// True while a continuous-mode start is awaiting `startRecording()`.
    /// A second lock press during this window flips
    /// `continuousStartCancelled` so the post-start code discards the
    /// recording instead of entering continuous mode.
    private var continuousStartInFlight = false
    private var continuousStartCancelled = false
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
    private var llmEnabledCancellable: AnyCancellable?
    private var retroactivePolishTask: Task<Void, Never>?
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
        audioRecorder.preferredDeviceUID = settings.preferredMicUID.isEmpty ? nil : settings.preferredMicUID
        PushToTalkService.setTrigger(AppState.resolveTrigger(settings))
        PushToTalkService.setLockTrigger(AppState.resolveLockTrigger(settings))
        SoundService.shared.isEnabled = settings.playSounds
        applyLaunchAtLoginSetting()
        showOnboardingIfNeeded()
        observeAudioLevel()
        observeMicSetting()
        observeTriggerSetting()
        observePresetSetting()
        observeModelSetting()
        observeSoundSetting()
        observeLaunchSetting()
        observeLlmEnabledSetting()
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
            try pushToTalkService.start(
                onPress: { [weak self] in
                    Task { @MainActor in
                        self?.beginPushToTalkRecording()
                    }
                },
                onRelease: { [weak self] in
                    Task { @MainActor in
                        self?.endPushToTalkRecording()
                    }
                },
                onLockToggle: { [weak self] in
                    Task { @MainActor in
                        self?.toggleContinuousLock()
                    }
                }
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func beginPushToTalkRecording() {
        // While in continuous, the primary trigger acts as an explicit
        // stop. This is the user's escape hatch when the silence watchdog
        // doesn't trigger (noisy environment) or when they got into
        // continuous unintentionally via the lock combo.
        if pttMode == .continuous {
            stopContinuousAndTranscribe()
            return
        }

        guard status != .recording,
              status.canToggleRecording,
              !isStartingPushToTalkRecording else { return }

        isPushToTalkHeld = true
        isStartingPushToTalkRecording = true
        pttMode = .hold

        Task { @MainActor in
            await startRecording()
            isStartingPushToTalkRecording = false

            if !isPushToTalkHeld, status == .recording, pttMode == .hold {
                pttMode = .idle
                await stopAndTranscribe()
            }
        }
    }

    private func endPushToTalkRecording() {
        // In continuous mode the physical release of the primary trigger is
        // irrelevant — the session ends on silence or on another lock press.
        if pttMode == .continuous { return }

        guard isPushToTalkHeld else { return }
        isPushToTalkHeld = false

        if status == .recording {
            pttMode = .idle
            transcribeTask?.cancel()
            transcribeTask = Task { [weak self] in
                await self?.stopAndTranscribe()
            }
        }
    }

    /// Toggle entry point for the secondary "lock-in" hotkey. Starts a
    /// continuous (hands-free) recording, or stops one in progress.
    private func toggleContinuousLock() {
        if pttMode == .continuous {
            stopContinuousAndTranscribe()
            return
        }

        // Second tap arriving while we are still spinning up the audio
        // engine for a previous lock press. Flag the in-flight start as
        // cancelled — the async tail will discard the recording instead
        // of entering continuous mode.
        if continuousStartInFlight {
            continuousStartCancelled = true
            return
        }

        // Promote an active hold session into continuous without restarting
        // the audio stream — user pressed-and-held the primary trigger,
        // then tapped the lock combo to "lock in" before releasing.
        if status == .recording {
            isPushToTalkHeld = false
            enterContinuousMode()
            return
        }

        // Fresh start.
        guard status.canToggleRecording, !isStartingPushToTalkRecording else { return }
        isStartingPushToTalkRecording = true
        continuousStartInFlight = true
        continuousStartCancelled = false
        Task { @MainActor in
            await startRecording()
            isStartingPushToTalkRecording = false
            continuousStartInFlight = false

            if continuousStartCancelled {
                continuousStartCancelled = false
                discardActiveRecording()
                return
            }
            if status == .recording {
                enterContinuousMode()
            }
        }
    }

    /// Stops and discards an in-progress recording without going through
    /// the transcribe pipeline. Used when the user cancels a continuous
    /// start mid-spinup.
    private func discardActiveRecording() {
        guard status == .recording else { return }
        if let url = try? audioRecorder.stopRecording() {
            try? FileManager.default.removeItem(at: url)
        }
        pttMode = .idle
        status = .idle
        lastError = nil
        hudController.update(state: .hidden)
        stopEscapeMonitor()
    }

    private func enterContinuousMode() {
        pttMode = .continuous
        hudController.setContinuous(true)
        silenceWatchdog.start(
            level: audioRecorder.$levelDB.eraseToAnyPublisher()
        ) { [weak self] in
            self?.stopContinuousAndTranscribe()
        }
    }

    private func stopContinuousAndTranscribe() {
        silenceWatchdog.stop()
        hudController.setContinuous(false)
        guard pttMode == .continuous else { return }
        pttMode = .idle
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
            silenceWatchdog.stop()
            hudController.setContinuous(false)
            pttMode = .idle
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
        silenceWatchdog.stop()
        pttMode = .idle
        hudController.setContinuous(false)
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
        silenceWatchdog.stop()
        pushToTalkService.stop()
        await whisperService.shutdown()
        await llmRefiner.shutdown()
    }

    func showOnboardingIfNeeded() {
        let modelExists = FileManager.default.fileExists(atPath: settings.modelPath)
        let needsOnboarding = !settings.hasCompletedOnboarding || !modelExists
        guard needsOnboarding else { return }
        DispatchQueue.main.async { [weak self] in
            OnboardingWindowController.shared.show { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.scheduleWarmup()
            }
        }
    }

    func showOnboarding() {
        OnboardingWindowController.shared.show { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.scheduleWarmup()
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        clipboardService.copy(lastTranscript)
    }

    /// Tears the audio engine and whisper-server down and brings them back
    /// up. Used as a manual "Restart" recovery from the menu when the
    /// auto-recovery on sleep/wake or device change failed to catch a stuck
    /// state.
    func restartPipeline() {
        guard status != .recording, status != .transcribing else { return }
        let recorder = audioRecorder
        let service = whisperService
        Task { [weak self] in
            await recorder.restart()
            await service.shutdown()
            await MainActor.run {
                self?.scheduleWarmup()
            }
        }
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

    // When the user flips the LLM toggle from OFF to ON and there is
    // already a recent transcript sitting in `lastTranscript` / clipboard,
    // run polish on it retroactively. This lets the user dictate first,
    // re-read, and only then decide they want a polished version — no need
    // to re-record the whole sentence.
    private func observeLlmEnabledSetting() {
        llmEnabledCancellable = settings.$llmRefinementEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard enabled else { return }
                self?.polishLastTranscriptIfPossible()
            }
    }

    private func polishLastTranscriptIfPossible() {
        guard shouldRefine else { return }
        let original = lastTranscript
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Don't fight an in-flight transcription; that path will refine
        // its own output through the normal pipeline.
        guard status != .recording, status != .transcribing else { return }

        // Capture the pasteboard's monotonic change counter BEFORE the async
        // refinement starts. If it changes during the wait — because the
        // user copied a URL, a password, or anything else while waiting for
        // the LLM — we drop the polished result instead of trampling their
        // current clipboard with stale dictation text.
        let initialChangeCount = NSPasteboard.general.changeCount

        retroactivePolishTask?.cancel()
        retroactivePolishTask = Task { [weak self] in
            guard let self else { return }
            let savedStatus = self.status
            self.status = .transcribing
            self.hudController.update(state: .transcribing)

            // Generous budget here: this path is explicitly user-initiated
            // (they flipped the toggle), so a cold-start wait is acceptable.
            let polished = await self.llmRefiner.refine(
                original,
                style: .polish,
                serverBinaryPath: self.settings.llmServerBinaryPath,
                modelPath: self.settings.llmModelPath,
                maxTotalSeconds: 30.0
            )

            // Three-way staleness check before committing:
            //   1. Task wasn't cancelled (e.g. by a newer toggle event).
            //   2. lastTranscript hasn't been overwritten by a fresh dictation.
            //   3. Pasteboard hasn't been written by the user in the meantime.
            // Any failure -> drop result, restore status, leave clipboard alone.
            let stillFresh = !Task.isCancelled
                && self.lastTranscript == original
                && NSPasteboard.general.changeCount == initialChangeCount

            if stillFresh && polished != original {
                self.lastTranscript = polished
                self.clipboardService.copy(polished)
                self.status = .completed
                self.hudController.update(state: .completed(Self.previewSnippet(polished)))
            } else {
                self.status = savedStatus
                self.hudController.update(state: .hidden)
            }
        }
    }

    private static func previewSnippet(_ text: String) -> String {
        let prefix = text.prefix(72)
        return prefix.count < text.count ? String(prefix) + "…" : String(prefix)
    }

    // The Italian diacritic fixer is safe on auto / it / it-* / Italian
    // explicit language settings. For an explicit non-Italian language we
    // skip it so English/German/French dictations don't accidentally get
    // Italian accents grafted onto rare proper-noun substrings.
    private static func shouldRunDiacriticFixer(language: String) -> Bool {
        let lang = language.trimmingCharacters(in: .whitespaces).lowercased()
        if lang.isEmpty || lang == "auto" { return true }
        return lang == "it" || lang.hasPrefix("it-") || lang == "italian"
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

        let updateLockTrigger: () -> Void = { [weak self] in
            guard let self else { return }
            PushToTalkService.setLockTrigger(AppState.resolveLockTrigger(self.settings))
        }
        lockTriggerSettingCancellable = Publishers.MergeMany(
            settings.$lockTriggerID.map { _ in () }.eraseToAnyPublisher(),
            settings.$customLockTriggerKeycode.map { _ in () }.eraseToAnyPublisher(),
            settings.$customLockTriggerFlags.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { _ in updateLockTrigger() }
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

    static func resolveLockTrigger(_ settings: SettingsStore) -> PushToTalkTrigger? {
        let id = settings.lockTriggerID
        if id.isEmpty { return nil }
        if id == "custom" {
            // Custom slot configured but with no usable data — treat as
            // disabled rather than silently falling back to a preset.
            guard settings.customLockTriggerKeycode >= 0,
                  settings.customLockTriggerFlags != 0 else {
                return nil
            }
            let label = settings.customLockTriggerLabel.isEmpty
                ? PushToTalkTrigger.describe(keycode: settings.customLockTriggerKeycode,
                                             flags: settings.customLockTriggerFlags)
                : settings.customLockTriggerLabel
            return PushToTalkTrigger.make(
                id: "lock_custom",
                label: label,
                keycode: settings.customLockTriggerKeycode,
                flags: settings.customLockTriggerFlags
            )
        }
        // Match by exact ID against known presets. We deliberately avoid
        // `PushToTalkTrigger.byID` here because its `.fn` fallback would
        // silently turn a malformed/version-skewed lockTriggerID into a
        // hidden global hotkey on the fn key.
        return PushToTalkTrigger.all.first { $0.id == id }
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

            let whisperOutput = try await whisperService.transcribe(
                audioURL: audioURL,
                binaryPath: settings.whisperBinaryPath,
                modelPath: settings.modelPath,
                language: settings.language,
                params: currentDecodingParams,
                prompt: settings.initialPrompt
            )
            transcribeSucceeded = true

            // Deterministic Italian diacritic restoration: microsecond-fast.
            // Gated on Italian-friendly language settings (auto or it) so a
            // user explicitly transcribing English doesn't get false-positive
            // accent edits on words like "città" inside English brand names.
            let rawTranscript: String
            if Self.shouldRunDiacriticFixer(language: settings.language) {
                rawTranscript = ItalianDiacriticFixer.fix(whisperOutput)
            } else {
                rawTranscript = whisperOutput
            }

            // Optional refinement: never blocks or fails the pipeline. The
            // refiner returns the original on any timeout, error, or
            // implausible output (see LLMRefinerService.isPlausibleRefinement).
            // Always uses Polish style — the toggle is the only knob.
            let transcript: String
            if shouldRefine {
                transcript = await llmRefiner.refine(
                    rawTranscript,
                    style: .polish,
                    serverBinaryPath: settings.llmServerBinaryPath,
                    modelPath: settings.llmModelPath
                )
            } else {
                transcript = rawTranscript
            }

            lastTranscript = transcript
            clipboardService.copy(transcript)
            // Stats use the original word count and audio duration so toggling
            // refinement on/off doesn't double-count or skew the metric.
            accumulateTimeSaved(transcript: rawTranscript, audioURL: audioURL)

            var pasteWarning: String?
            if settings.autoPaste {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    try pasteService.paste()
                } catch {
                    pasteWarning = L10n.format(
                        "Copied to clipboard. Paste failed: %@",
                        error.localizedDescription
                    )
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

    // Refinement runs only when the user toggled it on AND a model + server
    // binary are configured. We surface configuration errors via lastError
    // so the menu bar can show them, but never throw or block the pipeline.
    private var shouldRefine: Bool {
        guard settings.llmRefinementEnabled else { return false }
        guard !settings.llmModelPath.isEmpty,
              FileManager.default.fileExists(atPath: settings.llmModelPath) else {
            return false
        }
        guard !settings.llmServerBinaryPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: settings.llmServerBinaryPath) else {
            return false
        }
        return true
    }

    private func accumulateTimeSaved(transcript: String, audioURL: URL) {
        let wordCount = transcript.split(separator: " ").count
        guard wordCount > 0 else { return }
        var audioDurationSeconds: Double = 0
        if let audioFile = try? AVAudioFile(forReading: audioURL) {
            audioDurationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        }
        let typingBaseline = 40.0  // WPM, general population average
        let savedSeconds = max(0, Double(wordCount) / typingBaseline * 60.0 - audioDurationSeconds)
        settings.totalTimeSavedSeconds += savedSeconds
    }
}
