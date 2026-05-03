import AppKit
import SwiftUI

struct OutputSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Copy transcript to clipboard", isOn: .constant(true))
                    .disabled(true)
                Toggle("Paste into active app", isOn: $settings.autoPaste)
                Toggle("Start/stop sounds", isOn: $settings.playSounds)
            } header: {
                Text("Output")
            } footer: {
                Text("Auto-paste needs Accessibility. Without it, the transcript stays in the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("Startup")
            } footer: {
                Text("If recording fails, check System Settings → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.hasAccessibility ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                    accessibilityStatusLabel
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(appState.hasAccessibility ? "Re-check" : "Grant…") {
                        appState.requestAccessibilityPermission()
                        openAccessibilitySettings()
                        appState.resetPushToTalk()
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    @ViewBuilder
    private var accessibilityStatusLabel: some View {
        if appState.hasAccessibility {
            Text("Accessibility granted")
        } else {
            Text("Accessibility missing")
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
