import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    @State private var devices: [AudioInputDevice] = []
    @State private var testRunning = false
    @State private var testPeakDB: Float? = nil
    @State private var testStatus: String = ""

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

            Section("Microphone") {
                Picker("Input device", selection: deviceBinding) {
                    Text("System default").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button(testRunning ? "Listening..." : "Test microphone (1.5s)") {
                        Task { await runTest() }
                    }
                    .disabled(testRunning)

                    if let db = testPeakDB {
                        let dbInt = Int(db.rounded())
                        Text("Peak: \(dbInt) dB - \(qualityLabel(db))")
                            .foregroundStyle(qualityColor(db))
                    }
                }

                if !testStatus.isEmpty {
                    Text(testStatus)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Button("Refresh devices") {
                    refreshDevices()
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

            Section("Push-to-Talk") {
                Picker("Hotkey", selection: $settings.pushToTalkTriggerID) {
                    ForEach(PushToTalkTrigger.all) { trigger in
                        Text(trigger.label).tag(trigger.id)
                    }
                }
                .pickerStyle(.menu)

                Text("Hold the chosen key (or combo) to record. Release to transcribe.")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Button("Request Accessibility Permission") {
                    appState.requestAccessibilityPermission()
                    appState.resetPushToTalk()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620, height: 580)
        .onAppear {
            refreshDevices()
        }
    }

    private var deviceBinding: Binding<String> {
        Binding(
            get: { settings.preferredMicUID },
            set: { settings.preferredMicUID = $0 }
        )
    }

    private func refreshDevices() {
        devices = AudioDeviceCatalog.inputDevices()
    }

    private func runTest() async {
        testRunning = true
        testPeakDB = nil
        testStatus = "Speak normally for ~1 second."
        let peak = await appState.runMicLevelTest(seconds: 1.5)
        testPeakDB = peak
        testRunning = false
        testStatus = peak > -45
            ? "Microphone is capturing audio."
            : "No audio detected. Check the device and macOS permissions."
    }

    private func qualityLabel(_ db: Float) -> String {
        switch db {
        case ..<(-55): "Silent"
        case ..<(-30): "Low"
        case ..<(-12): "Good"
        default: "Loud"
        }
    }

    private func qualityColor(_ db: Float) -> Color {
        switch db {
        case ..<(-45): .red
        case ..<(-20): .orange
        default: .green
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
