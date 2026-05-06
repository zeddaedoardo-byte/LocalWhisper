import AppKit
import SwiftUI

struct LLMSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var availableModels: [LLMModelEntry] = []
    @State private var downloading: String? = nil
    @State private var downloadError: String? = nil

    var body: some View {
        Form {
            Section {
                Toggle("Refine transcript with LLM", isOn: $settings.llmRefinementEnabled)
                    .disabled(!isReady)
                if !isReady {
                    Text(readinessHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("Style", selection: Binding(
                    get: { settings.llmRefinementStyle },
                    set: { settings.llmRefinementStyle = $0 }
                )) {
                    Text("Light — fix mechanics").tag(SettingsStore.RefinementStyle.light)
                    Text("Polish — rewrite as clean message").tag(SettingsStore.RefinementStyle.polish)
                }
                .pickerStyle(.radioGroup)
                .disabled(!isReady || !settings.llmRefinementEnabled)

                Text(styleExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Refinement")
            } footer: {
                Text("Light preserves your wording and only fixes accents, punctuation, and capitalization. Polish rewrites your dictation as a clean written message in the same language: removes \"cioè / secondo me\", normalizes register, splits run-on sentences. Polish needs ~2-3× more output and is meaningfully slower.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if availableModels.isEmpty {
                    Text("No GGUF models found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Model", selection: $settings.llmModelPath) {
                        Text("None").tag("")
                        ForEach(availableModels, id: \.path) { model in
                            Text(model.displayName).tag(model.path)
                        }
                    }
                }

                LabeledContent("Models folder") {
                    Text(ProjectPaths.llmModelsDir.path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Open folder") { openModelsFolder() }
                    Button("Refresh list") { reloadModels() }
                    Spacer()
                    Button("Browse for GGUF…") { browseForModel() }
                }
            } header: {
                Text("Selected model")
            }

            Section {
                ForEach(LLMModelCatalog.recommended) { model in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.name)
                                    .fontWeight(.medium)
                                Text(model.size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(model.latencyHint)
                                    .font(.caption)
                                    .foregroundStyle(model.fitsBudget ? .green : .orange)
                            }
                            Text(model.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if isInstalled(model) {
                            Text("Installed")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if downloading == model.filename {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Download") {
                                Task { await download(model) }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Recommended models")
            } footer: {
                Text("Latency target is 100-200ms per dictation. Smaller models hit it; larger ones have higher quality but add noticeable lag. All models work fully offline once downloaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Binary") {
                    Text(settings.llmServerBinaryPath.isEmpty ? "Not found" : settings.llmServerBinaryPath)
                        .foregroundStyle(settings.llmServerBinaryPath.isEmpty ? .red : .secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if settings.llmServerBinaryPath.isEmpty {
                    Text("Install with: brew install llama.cpp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Button("Browse for llama-server…") { browseForBinary() }
            } header: {
                Text("llama-server")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { reloadModels() }
    }

    private var styleExplanation: String {
        switch settings.llmRefinementStyle {
        case .light:
            return "Example: \"perche cosi non perdiamo tempo\" → \"Perché così non perdiamo tempo.\""
        case .polish:
            return "Example: \"il psg ha segnato dopo due minuti e sono in vantaggio cioè secondo me la pareggiano\" → \"Il PSG ha segnato dopo due minuti ed è in vantaggio. A mio avviso, pareggeranno.\""
        }
    }

    private var isReady: Bool {
        !settings.llmServerBinaryPath.isEmpty &&
        FileManager.default.isExecutableFile(atPath: settings.llmServerBinaryPath) &&
        !settings.llmModelPath.isEmpty &&
        FileManager.default.fileExists(atPath: settings.llmModelPath)
    }

    private var readinessHint: String {
        if settings.llmServerBinaryPath.isEmpty {
            return "llama-server binary missing."
        }
        if settings.llmModelPath.isEmpty {
            return "Pick a model below or download one."
        }
        return ""
    }

    private func reloadModels() {
        let dir = ProjectPaths.llmModelsDir
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            availableModels = []
            return
        }
        availableModels = urls
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .map { LLMModelEntry(path: $0.path, displayName: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.displayName < $1.displayName }
    }

    private func openModelsFolder() {
        let dir = ProjectPaths.llmModelsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func browseForModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gguf") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.llmModelPath = url.path
            reloadModels()
        }
    }

    private func browseForBinary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.llmServerBinaryPath = url.path
        }
    }

    private func isInstalled(_ model: LLMModelCatalog.Recommended) -> Bool {
        let target = ProjectPaths.llmModelsDir.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: target.path)
    }

    private func download(_ model: LLMModelCatalog.Recommended) async {
        downloadError = nil
        downloading = model.filename
        defer { downloading = nil }

        let dir = ProjectPaths.llmModelsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(model.filename)

        do {
            guard let url = URL(string: model.url) else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            // HuggingFace serves some repos behind UA-checked CDN; a real
            // browser UA is enough to avoid spurious 401s.
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (tmpURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            settings.llmModelPath = dest.path
            reloadModels()
        } catch {
            downloadError = "Download failed: \(error.localizedDescription)"
        }
    }
}

struct LLMModelEntry: Hashable {
    let path: String
    let displayName: String
}

enum LLMModelCatalog {
    struct Recommended: Identifiable {
        let id = UUID()
        let name: String
        let size: String
        let latencyHint: String
        let fitsBudget: Bool
        let note: String
        let filename: String
        let url: String
    }

    // Ordered fastest -> highest quality. Latency hints are for a warm
    // process with cached system prompt and ~50 token output, on a base
    // M3 Air. M2 Air is ~30% slower; M4 Air is ~20% faster.
    static let recommended: [Recommended] = [
        Recommended(
            name: "Gemma 3 270M Instruct",
            size: "~200 MB",
            latencyHint: "~200 ms",
            fitsBudget: true,
            note: "Speed champion. Multilingual (256K vocab efficient on Italian). Fits the latency budget. Quality OK for trivial fixes.",
            filename: "Gemma-3-270m-it-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q4_K_M.gguf"
        ),
        Recommended(
            name: "Qwen 3 0.6B",
            size: "378 MB",
            latencyHint: "~400 ms",
            fitsBudget: false,
            note: "Latest small Qwen. Strong instruction following. Italian tokenizer ~15% less efficient than Gemma.",
            filename: "Qwen3-0.6B-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf"
        ),
        Recommended(
            name: "Gemma 3 1B Instruct",
            size: "~750 MB",
            latencyHint: "~1 s",
            fitsBudget: false,
            note: "Same Gemma 3 multilingual training as 4B in a smaller package. Solid quality/speed balance.",
            filename: "Gemma-3-1b-it-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf"
        ),
        Recommended(
            name: "Gemma 3 4B Instruct (Quality)",
            size: "2.49 GB",
            latencyHint: "~2-3 s",
            fitsBudget: false,
            note: "Quality champion for Italian. Best non-fine-tuned small model on Evalita-LLM CLiC-it 2025. Use when accuracy matters more than paste latency.",
            filename: "gemma-3-4b-it-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf"
        )
    ]
}
