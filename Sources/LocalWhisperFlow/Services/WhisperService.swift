import Foundation

enum WhisperError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            "whisper.cpp binary not found or not executable: \(path)"
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
    func transcribe(
        audioURL: URL,
        binaryPath: String,
        modelPath: String,
        language: String
    ) async throws -> String {
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: binaryPath) else {
            throw WhisperError.missingBinary(binaryPath)
        }

        guard fileManager.fileExists(atPath: modelPath) else {
            throw WhisperError.missingModel(modelPath)
        }

        let outputBase = fileManager.temporaryDirectory
            .appendingPathComponent("local-whisperflow-transcript-\(UUID().uuidString)")

        let arguments = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language.isEmpty ? "it" : language,
            "-otxt",
            "-of", outputBase.path,
            "-nt",
            "-ng"
        ]

        let result = try await runWhisper(binaryPath: binaryPath, arguments: arguments)
        let transcriptURL = outputBase.appendingPathExtension("txt")

        let rawText: String
        if fileManager.fileExists(atPath: transcriptURL.path) {
            rawText = try String(contentsOf: transcriptURL, encoding: .utf8)
        } else {
            rawText = result.standardOutput
        }

        let transcript = cleanTranscript(rawText)
        guard !transcript.isEmpty else {
            let diagnostic = result.standardError.isEmpty ? result.standardOutput : result.standardError
            if diagnostic.isEmpty {
                throw WhisperError.emptyTranscript
            }
            throw WhisperError.transcriptionFailed(diagnostic)
        }

        return transcript
    }

    private func runWhisper(
        binaryPath: String,
        arguments: [String]
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let standardOutput = String(
                        data: stdout.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let standardError = String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""

                    guard process.terminationStatus == 0 else {
                        let message = standardError.isEmpty ? standardOutput : standardError
                        throw WhisperError.transcriptionFailed(message)
                    }

                    continuation.resume(
                        returning: ProcessResult(
                            standardOutput: standardOutput,
                            standardError: standardError
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func cleanTranscript(_ rawText: String) -> String {
        rawText
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*\[[^\]]+\]\s*"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct ProcessResult {
    let standardOutput: String
    let standardError: String
}
