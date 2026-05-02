import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.status.title)
                .font(.headline)

            Text("Model: Whisper Large V3")
                .foregroundStyle(.secondary)

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript)
                    .lineLimit(4)
            }

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            Divider()

            Button(appState.status.primaryActionTitle) {
                appState.toggleRecording()
            }
            .disabled(!appState.status.canToggleRecording)

            Toggle("Auto Paste", isOn: $settings.autoPaste)

            Button("Request Accessibility Permission") {
                appState.requestAccessibilityPermission()
            }

            SettingsLink {
                Text("Settings")
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .frame(width: 280)
        .padding(.vertical, 6)
    }
}
