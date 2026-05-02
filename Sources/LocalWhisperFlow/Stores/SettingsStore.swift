import Foundation

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let modelPath = "modelPath"
        static let language = "language"
        static let autoPaste = "autoPaste"
        static let preferredMicUID = "preferredMicUID"
        static let pushToTalkTriggerID = "pushToTalkTriggerID"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedBinary = defaults.string(forKey: Keys.whisperBinaryPath)
        let resolvedBinary = SettingsStore.defaultWhisperBinaryPath()
        if let storedBinary, FileManager.default.isExecutableFile(atPath: storedBinary) {
            self.whisperBinaryPath = storedBinary
        } else {
            self.whisperBinaryPath = resolvedBinary
            defaults.set(resolvedBinary, forKey: Keys.whisperBinaryPath)
        }

        let storedModel = defaults.string(forKey: Keys.modelPath)
        let resolvedModel = ProjectPaths.defaultModelURL.path
        if let storedModel, FileManager.default.fileExists(atPath: storedModel) {
            self.modelPath = storedModel
        } else {
            self.modelPath = resolvedModel
            defaults.set(resolvedModel, forKey: Keys.modelPath)
        }

        self.language = defaults.string(forKey: Keys.language) ?? "it"
        self.autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        self.preferredMicUID = defaults.string(forKey: Keys.preferredMicUID) ?? ""
        self.pushToTalkTriggerID = defaults.string(forKey: Keys.pushToTalkTriggerID) ?? PushToTalkTrigger.fn.id
    }

    func resetDefaultPaths() {
        whisperBinaryPath = SettingsStore.defaultWhisperBinaryPath()
        modelPath = ProjectPaths.defaultModelURL.path
    }

    private static func defaultWhisperBinaryPath() -> String {
        let candidates = [
            ProjectPaths.projectRoot
                .appendingPathComponent("external/whisper.cpp/build/bin/whisper-cli")
                .path,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[0]
    }
}
