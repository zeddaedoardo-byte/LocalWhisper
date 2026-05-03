import AppKit
import SwiftUI

struct OutputSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Copia trascritto negli appunti", isOn: .constant(true))
                    .disabled(true)
                Toggle("Incolla nell'app attiva", isOn: $settings.autoPaste)
                Toggle("Suoni di start/stop", isOn: $settings.playSounds)
            } header: {
                Text("Output")
            } footer: {
                Text("Auto-paste richiede Accessibility. Senza, il testo resta solo negli appunti.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Avvia all'accesso al Mac", isOn: $settings.launchAtLogin)
            } header: {
                Text("Avvio")
            } footer: {
                Text("Se la registrazione fallisce, controlla System Settings → Login Items.")
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
