import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.status.title)
                .font(.headline)

            Text("Model: Whisper Large V3 (Metal)")
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isServerReady ? Color.green : (appState.isWarmingUp ? Color.orange : Color.gray))
                    .frame(width: 8, height: 8)
                Text(appState.isServerReady ? "Server ready" : (appState.isWarmingUp ? "Warming up..." : "Server stopped"))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.hasAccessibility ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.hasAccessibility ? "Accessibility OK" : "Accessibility missing")
                    .foregroundStyle(.secondary)
            }

            Text("Hold \(PushToTalkTrigger.byID(settings.pushToTalkTriggerID).label) to record")
                .foregroundStyle(.secondary)

            Text("Tap events: \(appState.tapEventsReceived)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "Flags: 0x%08llx  kc:%d", appState.lastTapFlags, appState.lastTapKeycode))
                .font(.caption2)
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

            if !appState.hasAccessibility {
                Button("Grant Accessibility...") {
                    appState.requestAccessibilityPermission()
                    openAccessibilitySettings()
                }
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

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
