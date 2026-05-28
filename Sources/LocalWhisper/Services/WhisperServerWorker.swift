import Foundation
import Darwin

actor WhisperServerWorker {
    nonisolated(unsafe) private static var pidRegistry: Set<pid_t> = []
    private static let pidRegistryLock = NSLock()

    static func registerPID(_ pid: pid_t) {
        pidRegistryLock.lock()
        pidRegistry.insert(pid)
        pidRegistryLock.unlock()
    }

    static func unregisterPID(_ pid: pid_t) {
        pidRegistryLock.lock()
        pidRegistry.remove(pid)
        pidRegistryLock.unlock()
    }

    static func terminateAllRunningServers() {
        pidRegistryLock.lock()
        let snapshot = pidRegistry
        pidRegistry.removeAll()
        pidRegistryLock.unlock()
        for pid in snapshot where pid > 0 {
            kill(pid, SIGTERM)
        }
    }

    private let host = "127.0.0.1"
    let port: Int

    struct DecodingParams: Equatable {
        let beamSize: Int
        let bestOf: Int
        let audioContext: Int
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var currentBinary: String?
    private var currentModel: String?
    private var currentParams: DecodingParams?
    private var readyTask: Task<Void, Error>?
    private var stderrBuffer = ""

    init(port: Int = 18642) {
        self.port = port
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func ensureRunning(serverBinaryPath: String, modelPath: String, params: DecodingParams) async throws {
        if let proc = process,
           proc.isRunning,
           currentBinary == serverBinaryPath,
           currentModel == modelPath,
           currentParams == params {
            try await waitReady()
            return
        }

        await stop()
        try start(serverBinaryPath: serverBinaryPath, modelPath: modelPath, params: params)
        try await waitReady()
    }

    func transcribe(audioURL: URL, language: String, prompt: String = "") async throws -> String {
        let endpoint = URL(string: "http://\(host):\(port)/inference")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let lang = language.isEmpty ? "auto" : language
        let audioData = try Data(contentsOf: audioURL)

        var body = Data()
        body.appendField(name: "language", value: lang, boundary: boundary)
        body.appendField(name: "response_format", value: "text", boundary: boundary)
        body.appendField(name: "temperature", value: "0.0", boundary: boundary)
        body.appendField(name: "temperature_inc", value: "0.2", boundary: boundary)
        // Optional initial prompt: biases the decoder toward specific
        // vocabulary, brand spellings, and acronyms. Whisper truncates
        // anything beyond ~224 tokens, so a short hint of frequent terms is
        // the most effective shape.
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            body.appendField(name: "prompt", value: trimmedPrompt, boundary: boundary)
        }
        body.appendFile(name: "file",
                        filename: audioURL.lastPathComponent,
                        mimeType: "audio/wav",
                        data: audioData,
                        boundary: boundary)
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhisperError.transcriptionFailed("Whisper server returned no HTTP response.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WhisperError.transcriptionFailed("Whisper server HTTP \(http.statusCode): \(body)")
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw WhisperError.emptyTranscript
        }
        return cleaned
    }

    func stop() async {
        readyTask?.cancel()
        readyTask = nil

        if let proc = process {
            let pid = proc.processIdentifier
            await Self.terminate(process: proc, pid: pid)
            WhisperServerWorker.unregisterPID(pid)
        }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        currentBinary = nil
        currentModel = nil
        currentParams = nil
        stderrBuffer = ""
    }

    private static func terminate(process proc: Process, pid: pid_t) async {
        guard proc.isRunning else { return }

        // 1. SIGTERM via Process.terminate(), wait up to 3 s.
        proc.terminate()
        for _ in 0..<30 where proc.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !proc.isRunning { return }

        // 2. SIGINT via Process.interrupt(), wait up to 1.5 s.
        proc.interrupt()
        for _ in 0..<15 where proc.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !proc.isRunning { return }

        // 3. Last resort: SIGKILL. The process cannot ignore this.
        kill(pid, SIGKILL)
        for _ in 0..<20 where proc.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func start(serverBinaryPath: String, modelPath: String, params: DecodingParams) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: serverBinaryPath) else {
            throw WhisperError.missingBinary(serverBinaryPath)
        }
        guard fm.fileExists(atPath: modelPath) else {
            throw WhisperError.missingModel(modelPath)
        }

        var arguments: [String] = [
            "-m", modelPath,
            "--host", host,
            "--port", String(port),
            "-nt",
            "-fa",
            "-bs", String(params.beamSize),
            "-bo", String(params.bestOf),
            "-ac", String(params.audioContext)
        ]

        // If a silero VAD model is present in the same directory as the gguf,
        // enable Voice Activity Detection so the encoder receives speech-only
        // input. This eliminates silence-padding hallucinations on short
        // utterances and shaves the encoder cost a bit on top.
        let modelDir = (modelPath as NSString).deletingLastPathComponent
        let vadPath = (modelDir as NSString).appendingPathComponent("ggml-silero-v5.1.2.bin")
        if fm.fileExists(atPath: vadPath) {
            arguments.append(contentsOf: [
                "--vad",
                "--vad-model", vadPath
            ])
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverBinaryPath)
        proc.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        let captureBuffer = StderrBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            // Empty data means EOF (child closed the pipe). Tear down the
            // dispatch source, otherwise it re-fires forever and spins a core.
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            captureBuffer.append(text)
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        try proc.run()
        WhisperServerWorker.registerPID(proc.processIdentifier)
        process = proc
        stdoutPipe = stdout
        stderrPipe = stderr
        currentBinary = serverBinaryPath
        currentModel = modelPath
        currentParams = params
        stderrBuffer = ""

        let host = self.host
        let port = self.port
        readyTask = Task.detached {
            try await WhisperServerWorker.pollReady(host: host, port: port, buffer: captureBuffer, process: proc)
        }
    }

    private func waitReady() async throws {
        guard let task = readyTask else { return }
        try await task.value
    }

    private static func pollReady(host: String,
                                  port: Int,
                                  buffer: StderrBuffer,
                                  process: Process,
                                  timeout: TimeInterval = 600) async throws {
        let url = URL(string: "http://\(host):\(port)/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            if !process.isRunning {
                let snapshot = buffer.snapshot()
                throw WhisperError.transcriptionFailed("Whisper server exited before ready: \(snapshot)")
            }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                    return
                }
            } catch {
                // server not yet listening; keep polling
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        throw WhisperError.transcriptionFailed("Whisper server failed to start within \(Int(timeout))s.")
    }
}

private final class StderrBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "whisper.server.stderr")
    private var text = ""

    func append(_ chunk: String) {
        queue.sync { text.append(chunk) }
    }

    func snapshot() -> String {
        queue.sync { text }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func appendFile(name: String,
                             filename: String,
                             mimeType: String,
                             data: Data,
                             boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
