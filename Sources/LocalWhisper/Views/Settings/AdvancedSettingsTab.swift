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
                LabeledContent("Push-to-talk log") {
                    Text("/tmp/lwf-ptt.log")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .monospaced()
                }
                Button("Reveal log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/tmp/lwf-ptt.log")])
                }
            } header: {
                Text("Diagnostics")
            }

            Section {
                if let failed = appState.lastFailedAudioURL {
                    LabeledContent("Last failed audio") {
                        Text(failed.lastPathComponent)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([failed])
                        }
                        Button("Delete") {
                            appState.clearLastFailedAudio()
                        }
                    }
                } else {
                    Text("No failed audio retained.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text("When a transcription fails the WAV is kept here so you can recover it. Successful transcriptions are deleted immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
