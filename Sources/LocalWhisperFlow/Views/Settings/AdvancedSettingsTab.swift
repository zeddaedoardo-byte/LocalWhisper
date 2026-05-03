import AppKit
import SwiftUI

struct AdvancedSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Server endpoint") {
                    Text("http://127.0.0.1:18642")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .monospaced()
                }
                LabeledContent("Model path") {
                    Text(settings.modelPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Restart Whisper server") {
                    appState.scheduleWarmup()
                }
            } header: {
                Text("Server")
            }

            Section {
                LabeledContent("Log push-to-talk") {
                    Text("/tmp/lwf-ptt.log")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .monospaced()
                }
                Button("Mostra log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/tmp/lwf-ptt.log")])
                }
            } header: {
                Text("Diagnostica")
            }

            Section {
                if let failed = appState.lastFailedAudioURL {
                    LabeledContent("Ultimo audio fallito") {
                        Text(failed.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Mostra in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([failed])
                        }
                        Button("Elimina") {
                            appState.clearLastFailedAudio()
                        }
                    }
                } else {
                    Text("Nessun audio fallito conservato.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recupero")
            } footer: {
                Text("Quando una trascrizione fallisce il WAV viene conservato qui per permetterti di recuperarlo. Le trascrizioni riuscite vengono cancellate subito.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
