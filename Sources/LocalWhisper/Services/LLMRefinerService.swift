import Foundation

// High-level facade over the llama-server worker. Public API is a single
// `refine(_:)` call that returns the original text on any failure, timeout,
// or implausible refinement. The dictation pipeline can therefore enable this
// unconditionally without ever blocking or corrupting the user's transcript.
final class LLMRefinerService {
    private let worker: LLMServerWorker
    private let session: URLSession

    // Hard cap on the round-trip. Anything slower than this is unacceptable
    // for a paste-immediate-on-release UX. URLSession's per-request timeout
    // also enforces it from outside the response stream.
    private let refineTimeout: TimeInterval = 1.5

    init(worker: LLMServerWorker = LLMServerWorker()) {
        self.worker = worker

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = self.refineTimeout
        config.timeoutIntervalForResource = self.refineTimeout
        // Keepalive: refinements are frequent and small. Reusing connections
        // shaves the TCP handshake on every request.
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    func warmup(serverBinaryPath: String, modelPath: String) async throws {
        try await worker.ensureRunning(serverBinaryPath: serverBinaryPath, modelPath: modelPath)
    }

    func shutdown() async {
        await worker.stop()
    }

    // Returns the refined text on success, or `original` on any failure.
    // Never throws; caller doesn't need to handle errors — this is a quality
    // booster, not a critical step in the pipeline.
    func refine(_ original: String, serverBinaryPath: String, modelPath: String) async -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }

        do {
            try await worker.ensureRunning(serverBinaryPath: serverBinaryPath, modelPath: modelPath)
            guard let endpoint = await worker.endpoint else { return original }

            let refined = try await postRefinement(text: trimmed, baseURL: endpoint)
            if Self.isPlausibleRefinement(original: trimmed, refined: refined) {
                return refined
            }
            return original
        } catch {
            return original
        }
    }

    private func postRefinement(text: String, baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = refineTimeout

        // Output budget heuristic: refinement should not balloon the text.
        // Cap at ~1.5x input characters (rough upper bound for tokens with
        // added punctuation/casing) to keep generation latency bounded.
        let maxTokens = max(40, min(200, Int(Double(text.count) * 0.6)))

        let payload: [String: Any] = [
            "model": "default",
            "temperature": 0.0,
            "top_p": 1.0,
            "n_predict": maxTokens,
            "max_tokens": maxTokens,
            "stream": false,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // System prompt is intentionally restrictive. The model's job is mechanical
    // cleanup, not paraphrasing. Every escape hatch ("if unsure, repeat input
    // verbatim") is here to protect against creative LLMs that "improve" the
    // text by adding apologies or commentary.
    private static let systemPrompt = """
    You correct dictation transcripts. Your only job is to fix typos, capitalization, and punctuation.

    Rules:
    - Preserve every word the user said.
    - Preserve named entities, technical terms, acronyms, and numbers exactly.
    - Do not add, remove, reorder, or rephrase content.
    - Do not add commentary, explanations, or quotation marks.
    - If the input is already correct or you are unsure, return it unchanged.

    Output only the corrected text. Nothing else.
    """

    // Diff guard: a "refinement" that changes the length drastically is
    // almost always a hallucination (the model went off-script and rewrote
    // the sentence). Reject those and fall back to the original transcript.
    private static func isPlausibleRefinement(original: String, refined: String) -> Bool {
        guard !refined.isEmpty else { return false }
        let originalLen = max(original.count, 1)
        let refinedLen = refined.count
        let ratio = Double(refinedLen) / Double(originalLen)
        if ratio < 0.5 || ratio > 1.5 {
            return false
        }
        // Reject if refined includes obvious commentary tokens that the
        // model sometimes leaks despite the system prompt.
        let suspicious = ["here is", "corrected:", "here's", "I have", "fixed:", "</s>", "<|"]
        let lower = refined.lowercased()
        for token in suspicious where lower.contains(token) {
            return false
        }
        return true
    }
}
