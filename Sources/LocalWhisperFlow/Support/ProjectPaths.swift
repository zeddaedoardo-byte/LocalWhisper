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

    static var defaultModelURL: URL {
        projectRoot.appendingPathComponent("Models/ggml-large-v3.bin")
    }
}
