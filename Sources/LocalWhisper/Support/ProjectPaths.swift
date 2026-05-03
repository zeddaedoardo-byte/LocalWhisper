import Foundation

enum ProjectPaths {
    static var projectRoot: URL {
        let bundleURL = Bundle.main.bundleURL

        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let newDir = base.appendingPathComponent("LocalWhisper", isDirectory: true)

        // One-time migration from the legacy "LocalWhisperFlow" Application
        // Support directory. Models and last-failed audio survive the rename.
        let legacyDir = base.appendingPathComponent("LocalWhisperFlow", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: legacyDir.path), !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: legacyDir, to: newDir)
        }

        return newDir
    }

    static var applicationSupportModelsDir: URL {
        applicationSupportRoot.appendingPathComponent("Models", isDirectory: true)
    }

    static var defaultModelURL: URL {
        let asURL = applicationSupportModelsDir.appendingPathComponent("ggml-large-v3.bin")
        if FileManager.default.fileExists(atPath: asURL.path) {
            return asURL
        }
        let projectURL = projectRoot.appendingPathComponent("Models/ggml-large-v3.bin")
        if FileManager.default.fileExists(atPath: projectURL.path) {
            return projectURL
        }
        return asURL
    }
}
