import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Whisper") {
                PathPickerRow(
                    title: "whisper-cli",
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
            }

            Section("Output") {
                Toggle("Copy transcript to clipboard", isOn: .constant(true))
                    .disabled(true)
                Toggle("Paste into active app", isOn: $settings.autoPaste)

                Button("Request Accessibility Permission") {
                    appState.requestAccessibilityPermission()
                }
            }

            Section("Global Hotkey") {
                HStack {
                    Toggle("Command", isOn: modifierBinding(HotkeyDefaults.commandModifier))
                    Toggle("Option", isOn: modifierBinding(HotkeyDefaults.optionModifier))
                    Toggle("Control", isOn: modifierBinding(HotkeyDefaults.controlModifier))
                    Toggle("Shift", isOn: modifierBinding(HotkeyDefaults.shiftModifier))
                }

                Stepper("Key code: \(settings.hotkeyKeyCode)", value: $settings.hotkeyKeyCode, in: 0...127)

                HStack {
                    Button("Apply Hotkey") {
                        appState.registerHotkey()
                    }

                    Button("Reset Option-Space") {
                        settings.hotkeyModifiers = HotkeyDefaults.optionModifier
                        settings.hotkeyKeyCode = HotkeyDefaults.spaceKeyCode
                        appState.registerHotkey()
                    }
                }

                Text("Default: Option-Space. Space key code is 49.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620, height: 500)
    }

    private func modifierBinding(_ modifier: Int) -> Binding<Bool> {
        Binding {
            settings.hasHotkeyModifier(modifier)
        } set: { enabled in
            settings.setHotkeyModifier(modifier, enabled: enabled)
        }
    }
}

private struct PathPickerRow: View {
    let title: String
    @Binding var path: String
    let canChooseDirectories: Bool

    var body: some View {
        HStack {
            TextField(title, text: $path)
                .textFieldStyle(.roundedBorder)

            Button("Choose...") {
                choosePath()
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title)"
        panel.canChooseFiles = !canChooseDirectories
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}
