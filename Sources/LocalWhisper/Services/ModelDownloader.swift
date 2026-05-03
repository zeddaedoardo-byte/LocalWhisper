import Combine
import Foundation
import SwiftUI

@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloadingModel
        case downloadingCoreML
        case extractingCoreML

        var label: LocalizedStringKey {
            switch self {
            case .idle: ""
            case .downloadingModel: "Model"
            case .downloadingCoreML: "Core ML encoder"
            case .extractingCoreML: "Extracting Core ML"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var inFlightModelID: String?
    @Published private(set) var lastError: String?

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private var continuation: CheckedContinuation<URL, Error>?

    func downloadBundle(model: WhisperModelInfo, into destinationDir: URL, includeCoreML: Bool) async throws -> URL {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        inFlightModelID = model.id
        lastError = nil

        let modelURL = try await downloadModel(model, into: destinationDir)

        if includeCoreML, let encoderURL = model.coreMLEncoderURL {
            do {
                try await downloadAndExtractCoreML(model: model,
                                                    sourceURL: encoderURL,
                                                    modelsDir: destinationDir)
            } catch {
                // Core ML failure is non-fatal: the gguf model still works.
                lastError = "Core ML encoder non disponibile: \(error.localizedDescription)"
            }
        }

        inFlightModelID = nil
        phase = .idle
        return modelURL
    }

    func cancel() {
        task?.cancel()
        task = nil
        finishCleanup()
    }

    // MARK: - Model download

    private func downloadModel(_ model: WhisperModelInfo, into destinationDir: URL) async throws -> URL {
        let destination = destinationDir.appendingPathComponent(model.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        phase = .downloadingModel
        progress = 0
        bytesWritten = 0
        totalBytes = Int64(model.approxMB) * 1024 * 1024

        return try await runDownload(url: model.downloadURL, destination: destination)
    }

    // MARK: - Core ML

    private func downloadAndExtractCoreML(model: WhisperModelInfo,
                                          sourceURL: URL,
                                          modelsDir: URL) async throws {
        let encoderDir = modelsDir.appendingPathComponent(model.coreMLDirectoryName)
        if FileManager.default.fileExists(atPath: encoderDir.path) {
            return
        }

        phase = .downloadingCoreML
        progress = 0
        bytesWritten = 0
        totalBytes = Int64(model.coreMLEncoderApproxMB ?? 100) * 1024 * 1024

        let zipDestination = modelsDir.appendingPathComponent(model.coreMLDirectoryName + ".zip")
        if FileManager.default.fileExists(atPath: zipDestination.path) {
            try? FileManager.default.removeItem(at: zipDestination)
        }

        _ = try await runDownload(url: sourceURL, destination: zipDestination)

        phase = .extractingCoreML
        progress = 0
        try await Self.extractZip(at: zipDestination, into: modelsDir)
        try? FileManager.default.removeItem(at: zipDestination)
    }

    /// Runs unzip on a background thread so the MainActor (and the UI) stays
    /// responsive during extraction. Pipes are drained continuously so the
    /// child cannot block on a full stdout/stderr buffer.
    nonisolated private static func extractZip(at zipURL: URL, into destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                proc.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]

                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData
                }
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    _ = handle.availableData
                }

                do {
                    try proc.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                proc.waitUntilExit()

                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                guard proc.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "ModelDownloader",
                            code: 100,
                            userInfo: [
                                NSLocalizedDescriptionKey: L10n.format(
                                    "Core ML extraction failed (exit %d)",
                                    proc.terminationStatus
                                )
                            ]
                        )
                    )
                    return
                }
                continuation.resume()
            }
        }
    }

    // MARK: - URLSession

    private func runDownload(url: URL, destination: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        self.destination = destination

        let task = session.downloadTask(with: url)
        self.task = task
        task.resume()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.continuation = continuation
        }
    }

    private func finishCleanup() {
        session?.invalidateAndCancel()
        session = nil
        task = nil
        destination = nil
        progress = 0
        bytesWritten = 0
        totalBytes = 0
    }

    fileprivate func finish(success url: URL) {
        let cont = continuation
        continuation = nil
        let oldDestination = destination
        finishCleanup()
        // Restore destination flag for the resumed phase tracking (no-op now).
        _ = oldDestination
        cont?.resume(returning: url)
    }

    fileprivate func finish(error: Error) {
        let cont = continuation
        continuation = nil
        lastError = error.localizedDescription
        finishCleanup()
        inFlightModelID = nil
        phase = .idle
        cont?.resume(throwing: error)
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.bytesWritten = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.totalBytes = totalBytesExpectedToWrite
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fm = FileManager.default
        let tempCopy = fm.temporaryDirectory
            .appendingPathComponent("lwf-download-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: location, to: tempCopy)
        } catch {
            Task { @MainActor in self.finish(error: error) }
            return
        }

        Task { @MainActor in
            guard let destination = self.destination else {
                try? fm.removeItem(at: tempCopy)
                self.finish(error: NSError(domain: "ModelDownloader", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: "No destination configured."]))
                return
            }
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: tempCopy, to: destination)
                self.finish(success: destination)
            } catch {
                try? fm.removeItem(at: tempCopy)
                self.finish(error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in self.finish(error: error) }
    }
}
