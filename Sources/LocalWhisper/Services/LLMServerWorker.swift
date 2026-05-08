import Foundation
import Darwin

// Manages a long-running llama-server process for LLM refinement. Mirrors the
// shape of WhisperServerWorker but is intentionally lighter: a single endpoint,
// no decoding params, fail-fast readiness (the refinement is optional, so we'd
// rather give up quickly than block the dictation pipeline).
actor LLMServerWorker {
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

    enum LLMServerError: LocalizedError {
        case missingBinary(String)
        case missingModel(String)
        case startupFailed(String)
        case notReady

        var errorDescription: String? {
            switch self {
            case .missingBinary(let path):
                return "llama-server binary not found at \(path). Install with `brew install llama.cpp`."
            case .missingModel(let path):
                return "LLM model not found: \(path)"
            case .startupFailed(let reason):
                return "llama-server failed to start: \(reason)"
            case .notReady:
                return "llama-server is not ready."
            }
        }
    }

    private let host = "127.0.0.1"
    private(set) var port: Int = 0

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var currentBinary: String?
    private var currentModel: String?
    private var readyTask: Task<Void, Error>?

    var isRunning: Bool {
        process?.isRunning == true
    }

    var endpoint: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    func ensureRunning(serverBinaryPath: String, modelPath: String) async throws {
        if let proc = process,
           proc.isRunning,
           currentBinary == serverBinaryPath,
           currentModel == modelPath {
            try await waitReady()
            return
        }

        await stop()
        try start(serverBinaryPath: serverBinaryPath, modelPath: modelPath)
        try await waitReady()
    }

    func stop() async {
        readyTask?.cancel()
        readyTask = nil

        if let proc = process {
            let pid = proc.processIdentifier
            await Self.terminate(process: proc, pid: pid)
            LLMServerWorker.unregisterPID(pid)
        }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        currentBinary = nil
        currentModel = nil
        port = 0
    }

    private static func terminate(process proc: Process, pid: pid_t) async {
        guard proc.isRunning else { return }
        proc.terminate()
        for _ in 0..<20 where proc.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !proc.isRunning { return }
        kill(pid, SIGKILL)
        for _ in 0..<10 where proc.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func start(serverBinaryPath: String, modelPath: String) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: serverBinaryPath) else {
            throw LLMServerError.missingBinary(serverBinaryPath)
        }
        guard fm.fileExists(atPath: modelPath) else {
            throw LLMServerError.missingModel(modelPath)
        }

        // Ask the kernel for a free loopback port so we never collide with
        // whisper-server, with a stale instance, or with another local app.
        port = Self.allocateFreeLoopbackPort()

        // Performance tuning rationale:
        //   -ngl 99             : offload all layers to Metal on Apple Silicon.
        //   -c 1536             : context = system prompt (~400) + user (~150) +
        //                          generation (~150) + headroom. Smaller = faster
        //                          prefill, smaller KV cache.
        //   --flash-attn        : Apple Metal flash attention path. Lower memory
        //                          bandwidth and faster decode on M-series.
        //   --cache-type-k q8_0 : KV cache K/V tensors quantized to q8. Halves
        //   --cache-type-v q8_0   KV cache memory with no measurable quality
        //                          loss for short refinement contexts.
        //   --cache-reuse 256   : prefix-match incoming requests against the
        //                          last KV state. Our system prompt is identical
        //                          on every request, so this saves ~400-600 ms
        //                          of prefill per call after the first.
        //   --mlock             : lock weights in RAM. Prevents the macOS pager
        //                          from swapping out the model between dictations
        //                          (which would tank cold-warm latency).
        //   --threads -1        : let llama.cpp pick CPU thread count.
        // Note: recent llama-server versions (Homebrew, 2026) require an
        // explicit value for --flash-attn (on|off|auto). Passing the bare
        // flag silently swallows the next argument as its value, which
        // crashes startup with a confusing "unknown value" error.
        let arguments = [
            "-m", modelPath,
            "--host", host,
            "--port", String(port),
            "-c", "1536",
            "-ngl", "99",
            "--flash-attn", "on",
            "--cache-type-k", "q8_0",
            "--cache-type-v", "q8_0",
            "--cache-reuse", "256",
            "--mlock",
            "--threads", "-1"
        ]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverBinaryPath)
        proc.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        let captureBuffer = LLMStderrBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            captureBuffer.append(text)
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try proc.run()
        } catch {
            throw LLMServerError.startupFailed(error.localizedDescription)
        }
        LLMServerWorker.registerPID(proc.processIdentifier)
        process = proc
        stdoutPipe = stdout
        stderrPipe = stderr
        currentBinary = serverBinaryPath
        currentModel = modelPath

        let host = self.host
        let port = self.port
        readyTask = Task.detached {
            try await LLMServerWorker.pollReady(host: host, port: port, buffer: captureBuffer, process: proc)
        }
    }

    private func waitReady() async throws {
        guard let task = readyTask else { return }
        try await task.value
    }

    private static func pollReady(host: String,
                                  port: Int,
                                  buffer: LLMStderrBuffer,
                                  process: Process,
                                  timeout: TimeInterval = 60) async throws {
        // llama-server exposes /health for readiness; status 200 = loaded.
        let url = URL(string: "http://\(host):\(port)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            if !process.isRunning {
                throw LLMServerError.startupFailed(buffer.snapshot())
            }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                // Not listening yet.
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw LLMServerError.startupFailed("llama-server not ready within \(Int(timeout))s. \(buffer.snapshot())")
    }

    private static func allocateFreeLoopbackPort() -> Int {
        // BSD socket dance: bind to port 0 on loopback, read back the assigned
        // port, close. Brief TOCTOU window before llama-server binds; if it
        // collides the process exits and pollReady surfaces it.
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 0 }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, addrLen)
            }
        }
        guard bindResult == 0 else { return 0 }

        let getResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &addrLen)
            }
        }
        guard getResult == 0 else { return 0 }

        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

private final class LLMStderrBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "llm.server.stderr")
    private var text = ""

    func append(_ chunk: String) {
        queue.sync {
            text.append(chunk)
            // Keep only the last 4KB so memory stays bounded for long sessions.
            if text.count > 4096 {
                text = String(text.suffix(4096))
            }
        }
    }

    func snapshot() -> String {
        queue.sync { text }
    }
}
