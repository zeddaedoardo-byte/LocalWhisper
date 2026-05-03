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
            } header: {
                Text("Output")
            } footer: {
                Text("Auto-paste needs Accessibility. Without it, the transcript still lands in the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.hasAccessibility ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                    Text(appState.hasAccessibility ? "Accessibility granted" : "Accessibility missing")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(appState.hasAccessibility ? "Re-check" : "Grant...") {
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

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
