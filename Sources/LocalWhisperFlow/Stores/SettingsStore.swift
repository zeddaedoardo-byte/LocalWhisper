import Foundation

final class SettingsStore: ObservableObject {
    private enum Keys {
        static let whisperBinaryPath = "whisperBinaryPath"
        static let modelPath = "modelPath"
        static let language = "language"
        static let autoPaste = "autoPaste"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
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

    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.whisperBinaryPath = defaults.string(forKey: Keys.whisperBinaryPath)
            ?? SettingsStore.defaultWhisperBinaryPath()
        self.modelPath = defaults.string(forKey: Keys.modelPath)
            ?? ProjectPaths.defaultModelURL.path
        self.language = defaults.string(forKey: Keys.language) ?? "it"
        self.autoPaste = defaults.object(forKey: Keys.autoPaste) as? Bool ?? true
        self.hotkeyKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
            ?? HotkeyDefaults.spaceKeyCode
        self.hotkeyModifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
            ?? HotkeyDefaults.optionModifier
    }

    func resetDefaultPaths() {
        whisperBinaryPath = SettingsStore.defaultWhisperBinaryPath()
        modelPath = ProjectPaths.defaultModelURL.path
    }

    func hasHotkeyModifier(_ modifier: Int) -> Bool {
        (hotkeyModifiers & modifier) == modifier
    }

    func setHotkeyModifier(_ modifier: Int, enabled: Bool) {
        if enabled {
            hotkeyModifiers = hotkeyModifiers | modifier
        } else {
            hotkeyModifiers = hotkeyModifiers & ~modifier
        }
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
