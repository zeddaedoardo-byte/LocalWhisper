import AppKit
import SwiftUI

private struct LanguageOption: Identifiable {
    let id: String
    let label: LocalizedStringKey
}

private let kLanguageCatalog: [LanguageOption] = [
    .init(id: "auto", label: "Auto-detect"),
    .init(id: "it", label: "Italiano"),
    .init(id: "en", label: "English"),
    .init(id: "es", label: "Español"),
    .init(id: "fr", label: "Français"),
    .init(id: "de", label: "Deutsch"),
    .init(id: "pt", label: "Português"),
    .init(id: "nl", label: "Nederlands"),
    .init(id: "ru", label: "Русский"),
    .init(id: "zh", label: "中文"),
    .init(id: "ja", label: "日本語"),
    .init(id: "ko", label: "한국어"),
    .init(id: "ar", label: "العربية"),
    .init(id: "tr", label: "Türkçe")
]

struct WhisperSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var downloader = ModelDownloader()

    @State private var downloadError: String?
    @State private var modelPendingDeletion: WhisperModelInfo?

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: presetBinding) {
                    ForEach(PerformancePreset.allCases) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)

                Text(currentPreset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Beam size") {
                    Text("\(currentPreset.beamSize)")
                        .foregroundStyle(.secondary).monospaced()
                }
                LabeledContent("Best of") {
                    Text("\(currentPreset.bestOf)")
                        .foregroundStyle(.secondary).monospaced()
                }
                LabeledContent("Audio context") {
                    audioContextLabel
                        .foregroundStyle(.secondary).monospaced()
                }

                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                    Text("Suggested for your Mac: \(suggestedPresetLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") {
                        settings.performancePreset = HardwareProfile.current.suggestedPreset
                    }
                    .controlSize(.small)
                    .disabled(settings.performancePreset == HardwareProfile.current.suggestedPreset)
                }
            } header: {
                Text("Performance")
            }

            Section {
                ForEach(WhisperModelCatalog.models) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.label).font(.system(size: 13))
                                Text(model.filename).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()

                            if isCurrentModel(model) {
                                Label("Active", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .labelStyle(.iconOnly)
                                    .help("In use")
                            } else if isModelInstalled(model) {
                                Button("Use") { useModel(model) }
                                    .controlSize(.small)
                                Button {
                                    modelPendingDeletion = model
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from disk")
                            } else if downloader.inFlightModelID == model.id {
                                VStack(alignment: .trailing, spacing: 2) {
                                    ProgressView(value: downloader.progress).frame(width: 110)
                                    Text(downloader.phase.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button("Cancel") { downloader.cancel() }
                                    .controlSize(.small)
                            } else {
                                Button(downloadButtonLabel(for: model)) {
                                    Task { await downloadAndUse(model) }
                                }
                                .controlSize(.small)
                                .disabled(downloader.inFlightModelID != nil)
                            }
                        }

                        if isAppleSilicon, model.coreMLEncoderURL != nil, isModelInstalled(model) {
                            HStack(spacing: 6) {
                                Image(systemName: hasCoreML(model) ? "cpu.fill" : "cpu")
                                    .foregroundStyle(hasCoreML(model) ? .green : .secondary)
                                coreMLLabel(installed: hasCoreML(model))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !hasCoreML(model), downloader.inFlightModelID != model.id {
                                    Button("Download Core ML (\(model.coreMLEncoderApproxMB ?? 0) MB)") {
                                        Task { await downloadCoreMLOnly(model) }
                                    }
                                    .controlSize(.small)
                                    .disabled(downloader.inFlightModelID != nil)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }

                if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Models live in ~/Library/Application Support/LocalWhisper/Models. They replace the active model only after the download completes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: languageBinding) {
                    ForEach(kLanguageCatalog) { option in
                        Text(option.label).tag(option.id)
                    }
                    if !catalogContainsCurrentLanguage {
                        Text("Custom: \(settings.language)").tag(settings.language)
                    }
                }
                .pickerStyle(.menu)

                if isAuto {
                    Text("Whisper auto-detects the language for each dictation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Manual code")
                    TextField("e.g. it, en, auto", text: $settings.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                .font(.caption)
            } header: {
                Text("Language")
            }

            Section {
                PathPickerRow(
                    title: "whisper-cli binary",
                    path: $settings.whisperBinaryPath,
                    canChooseDirectories: false
                )
                PathPickerRow(
                    title: "Active model path",
                    path: $settings.modelPath,
                    canChooseDirectories: false
                )
                Button("Restore defaults") {
                    settings.resetDefaultPaths()
                }
            } header: {
                Text("Advanced (paths)")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .alert(item: $modelPendingDeletion) { model in
            Alert(
                title: Text("Delete \(model.label)?"),
                message: Text(deletionMessage(for: model)),
                primaryButton: .destructive(Text("Delete")) {
                    deleteModel(model)
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
    }

    @ViewBuilder
    private var audioContextLabel: some View {
        if currentPreset.audioContext == 0 {
            Text("full")
        } else {
            Text("\(currentPreset.audioContext)")
        }
    }

    @ViewBuilder
    private func coreMLLabel(installed: Bool) -> some View {
        if installed {
            Text("Core ML encoder installed (Neural Engine)")
        } else {
            Text("Core ML encoder not installed")
        }
    }

    private func deletionMessage(for model: WhisperModelInfo) -> String {
        L10n.format("Delete %@ confirmation", Int64(spaceUsed(by: model)))
    }

    // MARK: - Helpers

    private var currentPreset: PerformancePreset { settings.performancePreset }

    private var suggestedPresetLabel: String {
        HardwareProfile.current.suggestedPreset.label
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { settings.performancePresetID },
            set: { settings.performancePresetID = $0 }
        )
    }

    private var catalogContainsCurrentLanguage: Bool {
        kLanguageCatalog.contains { $0.id == settings.language }
    }

    private var isAuto: Bool {
        settings.language == "auto" || settings.language.isEmpty
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { settings.language.isEmpty ? "auto" : settings.language },
            set: { settings.language = $0 }
        )
    }

    private var isAppleSilicon: Bool {
        HardwareProfile.current.isAppleSilicon
    }

    private func hasCoreML(_ model: WhisperModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: coreMLDirURL(for: model).path)
    }

    private func downloadButtonLabel(for model: WhisperModelInfo) -> LocalizedStringKey {
        let modelMB = model.approxMB
        if isAppleSilicon, let coreMB = model.coreMLEncoderApproxMB {
            return "Download (\(modelMB) MB + \(coreMB) MB Core ML)"
        }
        return "Download (\(modelMB) MB)"
    }

    private func isModelInstalled(_ model: WhisperModelInfo) -> Bool {
        let path = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent(model.filename).path
        return FileManager.default.fileExists(atPath: path)
            || (settings.modelPath.hasSuffix(model.filename)
                && FileManager.default.fileExists(atPath: settings.modelPath))
    }

    private func isCurrentModel(_ model: WhisperModelInfo) -> Bool {
        URL(fileURLWithPath: settings.modelPath).lastPathComponent == model.filename
            && FileManager.default.fileExists(atPath: settings.modelPath)
    }

    private func useModel(_ model: WhisperModelInfo) {
        let path = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent(model.filename).path
        if FileManager.default.fileExists(atPath: path) {
            settings.modelPath = path
        }
    }

    private func spaceUsed(by model: WhisperModelInfo) -> Int {
        var total: Int64 = 0
        let modelURL = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent(model.filename)
        if let size = try? FileManager.default
            .attributesOfItem(atPath: modelURL.path)[.size] as? Int64 {
            total += size
        }
        let encoderURL = coreMLDirURL(for: model)
        if let enumerator = FileManager.default.enumerator(at: encoderURL,
                                                            includingPropertiesForKeys: [.fileSizeKey],
                                                            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return Int(total / (1024 * 1024))
    }

    private func deleteModel(_ model: WhisperModelInfo) {
        let fm = FileManager.default
        let modelURL = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent(model.filename)
        let encoderURL = coreMLDirURL(for: model)

        try? fm.removeItem(at: modelURL)
        try? fm.removeItem(at: encoderURL)

        // Cleanup MACOSX metadata folder that unzip may produce.
        let macosxDir = ProjectPaths.applicationSupportModelsDir
            .appendingPathComponent("__MACOSX")
        if fm.fileExists(atPath: macosxDir.path) {
            try? fm.removeItem(at: macosxDir)
        }
    }

    private func downloadAndUse(_ model: WhisperModelInfo) async {
        downloadError = nil
        let includeCoreML = HardwareProfile.current.isAppleSilicon && model.coreMLEncoderURL != nil
        do {
            let url = try await downloader.downloadBundle(
                model: model,
                into: ProjectPaths.applicationSupportModelsDir,
                includeCoreML: includeCoreML
            )
            settings.modelPath = url.path
        } catch {
            downloadError = L10n.format("Download failed: %@", error.localizedDescription)
        }
    }

    private func downloadCoreMLOnly(_ model: WhisperModelInfo) async {
        downloadError = nil
        guard let encoderURL = model.coreMLEncoderURL else { return }
        _ = encoderURL
        do {
            let url = try await downloader.downloadBundle(
                model: model,
                into: ProjectPaths.applicationSupportModelsDir,
                includeCoreML: true
            )
            settings.modelPath = url.path
        } catch {
            downloadError = L10n.format("Core ML download failed: %@", error.localizedDescription)
        }
    }

    fileprivate func coreMLDirURL(for model: WhisperModelInfo) -> URL {
        ProjectPaths.applicationSupportModelsDir.appendingPathComponent(model.coreMLDirectoryName)
    }
}
