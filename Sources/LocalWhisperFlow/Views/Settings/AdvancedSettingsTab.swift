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
                LabeledContent("Push-to-talk diagnostic log") {
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
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
