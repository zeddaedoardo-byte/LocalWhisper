import Foundation

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let modelPath = "modelPath"
        static let language = "language"
        static let autoPaste = "autoPaste"
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.whisperBinaryPath = defaults.string(forKey: Keys.whisperBinaryPath)
            ?? SettingsStore.defaultWhisperBinaryPath()
        self.modelPath = defaults.string(forKey: Keys.modelPath)
            ?? ProjectPaths.defaultModelURL.path
        self.language = defaults.string(forKey: Keys.language) ?? "it"
        self.autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
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
