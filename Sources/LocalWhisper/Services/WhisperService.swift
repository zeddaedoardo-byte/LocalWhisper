import Foundation

enum WhisperError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            "whisper-server binary not found or not executable: \(path)"
        case .missingModel(let path):
            "Whisper Large V3 model not found: \(path)"
        case .transcriptionFailed(let message):
            "Transcription failed: \(message)"
        case .emptyTranscript:
            "Transcription completed but produced empty text."
        }
    }
}

final class WhisperService {
    private let worker: WhisperServerWorker

    init(worker: WhisperServerWorker = WhisperServerWorker()) {
        self.worker = worker
    }

    func warmup(cliBinaryPath: String, modelPath: String, params: WhisperServerWorker.DecodingParams) async throws {
        let serverPath = Self.serverBinary(forCLIPath: cliBinaryPath)
        try await worker.ensureRunning(serverBinaryPath: serverPath, modelPath: modelPath, params: params)
    }

    func transcribe(
        audioURL: URL,
        binaryPath: String,
        modelPath: String,
        language: String,
        params: WhisperServerWorker.DecodingParams,
        prompt: String = ""
    ) async throws -> String {
        let serverPath = Self.serverBinary(forCLIPath: binaryPath)
        try await worker.ensureRunning(serverBinaryPath: serverPath, modelPath: modelPath, params: params)
        return try await worker.transcribe(audioURL: audioURL, language: language, prompt: prompt)
    }

    func shutdown() async {
        await worker.stop()
    }

    static func serverBinary(forCLIPath cliPath: String) -> String {
        let url = URL(fileURLWithPath: cliPath)
        let candidate = url
            .deletingLastPathComponent()
            .appendingPathComponent("whisper-server")
            .path
        return candidate
    }
}
