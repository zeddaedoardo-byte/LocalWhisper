import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case accessibility
        case model
        case done
    }

    @Published private(set) var step: Step = .welcome
    @Published private(set) var microphoneGranted: Bool = false
    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var modelInstalled: Bool = false
    @Published private(set) var modelDownloadProgress: Double = 0
    @Published private(set) var modelDownloadPhase: ModelDownloader.Phase = .idle
    @Published private(set) var modelDownloadError: String?
    @Published private(set) var isDownloadingModel: Bool = false

    private let downloader = ModelDownloader()
    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    let recommendedModel: WhisperModelInfo
    let suggestedPreset: PerformancePreset

    init() {
        let profile = HardwareProfile.current
        self.suggestedPreset = profile.suggestedPreset
        self.recommendedModel = OnboardingViewModel.recommendedModel(for: profile)

        refreshStatuses()
        startPolling()
        bindDownloader()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Step navigation

    var canAdvance: Bool {
        switch step {
        case .welcome: true
        case .microphone: microphoneGranted
        case .accessibility: accessibilityGranted
        case .model: modelInstalled
        case .done: true
        }
    }

    func advance() {
        guard canAdvance else { return }
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    // MARK: - Permissions

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshStatuses() }
        }
    }

    func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // Trigger the macOS prompt by querying with a prompt option, so the
        // app appears in the list even before it has tried to install a tap.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Model

    func downloadRecommendedModel() async {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        modelDownloadError = nil

        let useCoreML = HardwareProfile.current.isAppleSilicon && recommendedModel.coreMLEncoderURL != nil

        do {
            _ = try await downloader.downloadBundle(
                model: recommendedModel,
                into: ProjectPaths.applicationSupportModelsDir,
                includeCoreML: useCoreML
            )
            await fetchVADModelIfMissing()
            refreshStatuses()
        } catch {
            modelDownloadError = error.localizedDescription
        }

        isDownloadingModel = false
    }

    func cancelModelDownload() {
        downloader.cancel()
        isDownloadingModel = false
    }

    // MARK: - State refresh

    func refreshStatuses() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        modelInstalled = isRecommendedModelInstalled()
    }

    private func isRecommendedModelInstalled() -> Bool {
        let modelURL = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent(recommendedModel.filename)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatuses() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func bindDownloader() {
        downloader.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.modelDownloadProgress = $0 }
            .store(in: &cancellables)
        downloader.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.modelDownloadPhase = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private static func recommendedModel(for profile: HardwareProfile) -> WhisperModelInfo {
        // Apple Silicon with 16+ GB RAM: Turbo (1.5 GB) hits the sweet spot of
        // accuracy and speed. Smaller-RAM Apple Silicon and Intel Macs get
        // Medium for a smaller footprint and CPU-friendlier inference.
        if profile.isAppleSilicon, profile.physicalMemoryGB >= 12,
           let turbo = WhisperModelCatalog.info(forID: "large-v3-turbo") {
            return turbo
        }
        if let medium = WhisperModelCatalog.info(forID: "medium") {
            return medium
        }
        return WhisperModelCatalog.models.first!
    }

    private func fetchVADModelIfMissing() async {
        let url = URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!
        let dest = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent("ggml-silero-v5.1.2.bin")
        if FileManager.default.fileExists(atPath: dest.path) { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: dest)
        } catch {
            // VAD is non-fatal; the app runs without it.
        }
    }
}
