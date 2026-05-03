import AppKit
import SwiftUI

private struct LanguageOption: Identifiable, Hashable {
    let id: String
    let label: String
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
                    Text(currentPreset.audioContext == 0 ? "completo" : "\(currentPreset.audioContext)")
                        .foregroundStyle(.secondary).monospaced()
                }

                HStack {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                    Text("Suggerito per il tuo Mac: \(suggestedPresetLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Applica") {
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.label).font(.system(size: 13))
                            Text(model.filename).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()

                        if isCurrentModel(model) {
                            Label("Attivo", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.iconOnly)
                                .help("In uso")
                        } else if isModelInstalled(model) {
                            Button("Usa") {
                                useModel(model)
                            }
                            .controlSize(.small)
                        } else if downloader.inFlightModelID == model.id {
                            ProgressView(value: downloader.progress)
                                .frame(width: 100)
                            Button("Annulla") { downloader.cancel() }
                                .controlSize(.small)
                        } else {
                            Button("Scarica (\(model.approxMB) MB)") {
                                Task { await downloadAndUse(model) }
                            }
                            .controlSize(.small)
                            .disabled(downloader.inFlightModelID != nil)
                        }
                    }
                }

                if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Modello")
            } footer: {
                Text("I modelli vengono scaricati in ~/Library/Application Support/LocalWhisperFlow/Models e sostituiscono il modello attivo solo dopo il download completo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Lingua", selection: languageBinding) {
                    ForEach(kLanguageCatalog) { option in
                        Text(option.label).tag(option.id)
                    }
                    if !catalogContainsCurrentLanguage {
                        Text("Personalizzata: \(settings.language)").tag(settings.language)
                    }
                }
                .pickerStyle(.menu)

                if isAuto {
                    Text("Whisper rileva la lingua automaticamente per ogni dettatura.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Codice manuale")
                    TextField("es. it, en, auto", text: $settings.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                .font(.caption)
            } header: {
                Text("Lingua")
            }

            Section {
                PathPickerRow(
                    title: "whisper-cli binary",
                    path: $settings.whisperBinaryPath,
                    canChooseDirectories: false
                )
                PathPickerRow(
                    title: "Path modello attivo",
                    path: $settings.modelPath,
                    canChooseDirectories: false
                )
                Button("Ripristina default") {
                    settings.resetDefaultPaths()
                }
            } header: {
                Text("Avanzato (path)")
            }
        }
        .formStyle(.grouped)
        .padding(20)
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

    private func downloadAndUse(_ model: WhisperModelInfo) async {
        downloadError = nil
        do {
            let url = try await downloader.download(
                model: model,
                into: ProjectPaths.applicationSupportModelsDir
            )
            settings.modelPath = url.path
        } catch {
            downloadError = "Download fallito: \(error.localizedDescription)"
        }
    }
}
