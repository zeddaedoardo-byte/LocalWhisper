import Combine
import Foundation

@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    @Published private(set) var progress: Double = 0       // 0...1
    @Published private(set) var bytesWritten: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var inFlightModelID: String?
    @Published private(set) var lastError: String?

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private var continuation: CheckedContinuation<URL, Error>?

    func download(model: WhisperModelInfo, into destinationDir: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destination = destinationDir.appendingPathComponent(model.filename)

        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        self.destination = destination
        self.inFlightModelID = model.id
        self.progress = 0
        self.bytesWritten = 0
        self.totalBytes = Int64(model.approxMB) * 1024 * 1024
        self.lastError = nil

        let task = session.downloadTask(with: model.downloadURL)
        self.task = task
        task.resume()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.continuation = continuation
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        finishCleanup()
    }

    private func finishCleanup() {
        session?.invalidateAndCancel()
        session = nil
        task = nil
        destination = nil
        inFlightModelID = nil
        progress = 0
        bytesWritten = 0
        totalBytes = 0
    }

    fileprivate func finish(success url: URL) {
        let cont = continuation
        continuation = nil
        finishCleanup()
        cont?.resume(returning: url)
    }

    fileprivate func finish(error: Error) {
        let cont = continuation
        continuation = nil
        lastError = error.localizedDescription
        finishCleanup()
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
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("lwf-model-\(UUID().uuidString).bin")
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
