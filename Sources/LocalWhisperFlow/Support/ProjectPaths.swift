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
        return base.appendingPathComponent("LocalWhisperFlow", isDirectory: true)
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
