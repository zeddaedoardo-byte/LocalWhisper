import SwiftUI

struct WhisperSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                PathPickerRow(
                    title: "whisper-cli binary",
                    path: $settings.whisperBinaryPath,
                    canChooseDirectories: false
                )

                PathPickerRow(
                    title: "Large V3 model",
                    path: $settings.modelPath,
                    canChooseDirectories: false
                )

                TextField("Language", text: $settings.language)
                    .textFieldStyle(.roundedBorder)

                Button("Use Project Defaults") {
                    settings.resetDefaultPaths()
                }
            } header: {
                Text("Whisper engine")
            } footer: {
                Text("The whisper-server binary is auto-detected next to whisper-cli.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
