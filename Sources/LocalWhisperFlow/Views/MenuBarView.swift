import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: appState.status.systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(statusTint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(triggerHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 14) {
                StatusPill(
                    isOK: appState.isServerReady,
                    isLoading: appState.isWarmingUp,
                    label: appState.isServerReady ? "Server" : (appState.isWarmingUp ? "Warmup" : "Server")
                )
                StatusPill(
                    isOK: appState.hasAccessibility,
                    isLoading: false,
                    label: "Accessibility"
                )
            }

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript)
                    .font(.system(size: 12))
                    .lineLimit(4)
                    .foregroundStyle(.primary)
                Button {
                    appState.copyLastTranscript()
                } label: {
                    Label("Copy transcript", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.system(size: 11))
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
                Text("Settings...")
            }

            Divider()

            Button("Quit LocalWhisperFlow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .frame(width: 280)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusTint: Color {
        switch appState.status {
        case .idle: .secondary
        case .recording: .red
        case .transcribing: .blue
        case .completed: .green
        case .failed: .orange
        }
    }

    private var statusTitle: String {
        switch appState.status {
        case .idle: appState.isServerReady ? "Pronto" : "Caricamento Whisper..."
        case .recording: "Registrazione in corso"
        case .transcribing: "Trascrizione..."
        case .completed: "Pronto"
        case .failed: "Errore"
        }
    }

    private var triggerHint: String {
        let trigger = PushToTalkTrigger.byID(settings.pushToTalkTriggerID)
        return "Tieni \(trigger.label) per dettare"
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct StatusPill: View {
    let isOK: Bool
    let isLoading: Bool
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        if isOK { return .green }
        if isLoading { return .orange }
        return .red
    }
}
