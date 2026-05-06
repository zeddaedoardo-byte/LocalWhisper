import Foundation

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let modelPath = "modelPath"
        static let language = "language"
        static let autoPaste = "autoPaste"
        static let preferredMicUID = "preferredMicUID"
        static let pushToTalkTriggerID = "pushToTalkTriggerID"
        static let customTriggerKeycode = "customTriggerKeycode"
        static let customTriggerFlags = "customTriggerFlags"
        static let customTriggerLabel = "customTriggerLabel"
        static let performancePreset = "performancePreset"
        static let didSuggestPreset = "didSuggestPreset"
        static let launchAtLogin = "launchAtLogin"
        static let playSounds = "playSounds"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let totalTimeSavedSeconds = "totalTimeSavedSeconds"
        static let initialPrompt = "initialPrompt"
        static let llmRefinementEnabled = "llmRefinementEnabled"
        static let llmModelPath = "llmModelPath"
        static let llmServerBinaryPath = "llmServerBinaryPath"
    }

    private let defaults: UserDefaults

    @Published var whisperBinaryPath: String {
        didSet { defaults.set(whisperBinaryPath, forKey: Keys.whisperBinaryPath) }
    }

    @Published var modelPath: String {
        didSet { defaults.set(modelPath, forKey: Keys.modelPath) }
    }

    @Published var language: String {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }

    @Published var preferredMicUID: String {
        didSet {
            if preferredMicUID.isEmpty {
                defaults.removeObject(forKey: Keys.preferredMicUID)
            } else {
                defaults.set(preferredMicUID, forKey: Keys.preferredMicUID)
            }
        }
    }

    @Published var pushToTalkTriggerID: String {
        didSet { defaults.set(pushToTalkTriggerID, forKey: Keys.pushToTalkTriggerID) }
    }

    @Published var customTriggerKeycode: Int {
        didSet { defaults.set(customTriggerKeycode, forKey: Keys.customTriggerKeycode) }
    }

    @Published var customTriggerFlags: UInt64 {
        didSet { defaults.set(String(customTriggerFlags), forKey: Keys.customTriggerFlags) }
    }

    @Published var customTriggerLabel: String {
        didSet { defaults.set(customTriggerLabel, forKey: Keys.customTriggerLabel) }
    }

    @Published var performancePresetID: String {
        didSet { defaults.set(performancePresetID, forKey: Keys.performancePreset) }
    }

    var performancePreset: PerformancePreset {
        get { PerformancePreset(rawValue: performancePresetID) ?? .balanced }
        set { performancePresetID = newValue.rawValue }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published var totalTimeSavedSeconds: Double {
        didSet { defaults.set(totalTimeSavedSeconds, forKey: Keys.totalTimeSavedSeconds) }
    }

    @Published var initialPrompt: String {
        didSet { defaults.set(initialPrompt, forKey: Keys.initialPrompt) }
    }

    @Published var llmRefinementEnabled: Bool {
        didSet { defaults.set(llmRefinementEnabled, forKey: Keys.llmRefinementEnabled) }
    }

    @Published var llmModelPath: String {
        didSet { defaults.set(llmModelPath, forKey: Keys.llmModelPath) }
    }

    @Published var llmServerBinaryPath: String {
        didSet { defaults.set(llmServerBinaryPath, forKey: Keys.llmServerBinaryPath) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedBinary = defaults.string(forKey: Keys.whisperBinaryPath)
        let resolvedBinary = SettingsStore.defaultWhisperBinaryPath()
        let bundledBinary = SettingsStore.bundledWhisperBinaryPath()

        // Prefer the binary embedded in the running app bundle when available;
        // it is guaranteed to match the running app's signature.
        let chosenBinary: String
        if let bundledBinary {
            chosenBinary = bundledBinary
        } else if let storedBinary, FileManager.default.isExecutableFile(atPath: storedBinary) {
            chosenBinary = storedBinary
        } else {
            chosenBinary = resolvedBinary
        }
        self.whisperBinaryPath = chosenBinary
        defaults.set(chosenBinary, forKey: Keys.whisperBinaryPath)

        let storedModel = defaults.string(forKey: Keys.modelPath)
        let resolvedModel = ProjectPaths.defaultModelURL.path
        if let storedModel, FileManager.default.fileExists(atPath: storedModel) {
            self.modelPath = storedModel
        } else {
            self.modelPath = resolvedModel
            defaults.set(resolvedModel, forKey: Keys.modelPath)
        }

        self.language = defaults.string(forKey: Keys.language) ?? "auto"
        self.autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        self.preferredMicUID = defaults.string(forKey: Keys.preferredMicUID) ?? ""
        self.pushToTalkTriggerID = defaults.string(forKey: Keys.pushToTalkTriggerID) ?? PushToTalkTrigger.fn.id
        self.customTriggerKeycode = defaults.object(forKey: Keys.customTriggerKeycode) as? Int ?? -1
        self.customTriggerFlags = (defaults.string(forKey: Keys.customTriggerFlags).flatMap(UInt64.init)) ?? 0
        self.customTriggerLabel = defaults.string(forKey: Keys.customTriggerLabel) ?? ""

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.totalTimeSavedSeconds = defaults.double(forKey: Keys.totalTimeSavedSeconds)
        self.initialPrompt = defaults.string(forKey: Keys.initialPrompt) ?? ""
        self.llmRefinementEnabled = defaults.bool(forKey: Keys.llmRefinementEnabled)
        self.llmModelPath = defaults.string(forKey: Keys.llmModelPath) ?? ""
        // Re-detect on every launch when the stored path is empty or no
        // longer executable (e.g. the user installed llama.cpp after the
        // first launch, or moved it). A successful auto-detect overwrites
        // the stored value via didSet on first read of llmRefinementEnabled.
        let storedLlamaPath = defaults.string(forKey: Keys.llmServerBinaryPath) ?? ""
        if !storedLlamaPath.isEmpty && FileManager.default.isExecutableFile(atPath: storedLlamaPath) {
            self.llmServerBinaryPath = storedLlamaPath
        } else {
            self.llmServerBinaryPath = SettingsStore.defaultLlamaServerBinaryPath()
        }

        let didSuggest = defaults.bool(forKey: Keys.didSuggestPreset)
        let storedPreset = defaults.string(forKey: Keys.performancePreset)
        if let storedPreset, !storedPreset.isEmpty {
            self.performancePresetID = storedPreset
        } else if !didSuggest {
            self.performancePresetID = HardwareProfile.current.suggestedPreset.rawValue
            defaults.set(self.performancePresetID, forKey: Keys.performancePreset)
            defaults.set(true, forKey: Keys.didSuggestPreset)
        } else {
            self.performancePresetID = PerformancePreset.balanced.rawValue
        }
    }

    func resetDefaultPaths() {
        whisperBinaryPath = SettingsStore.defaultWhisperBinaryPath()
        modelPath = ProjectPaths.defaultModelURL.path
    }

    // Auto-detect a llama-server binary the first time the LLM refinement
    // setting is read. The user can install it via Homebrew (`brew install
    // llama.cpp`) or build from source. We don't hard-fail if missing — the
    // refinement toggle will surface the error in the menu when activated.
    private static func defaultLlamaServerBinaryPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "\(NSHomeDirectory())/.local/bin/llama-server"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    private static func bundledWhisperBinaryPath() -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("bin/whisper-cli").path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private static func defaultWhisperBinaryPath() -> String {
        var candidates: [String] = []

        if let bundled = bundledWhisperBinaryPath() {
            candidates.append(bundled)
        }

        candidates.append(
            ProjectPaths.applicationSupportRoot
                .appendingPathComponent("bin/whisper-cli")
                .path
        )
        candidates.append(
            ProjectPaths.projectRoot
                .appendingPathComponent("external/whisper.cpp/build/bin/whisper-cli")
                .path
        )
        candidates.append("/opt/homebrew/bin/whisper-cli")
        candidates.append("/usr/local/bin/whisper-cli")

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[0]
    }
}
