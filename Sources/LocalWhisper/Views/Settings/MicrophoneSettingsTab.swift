import SwiftUI

struct MicrophoneSettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    @State private var devices: [AudioInputDevice] = []
    @State private var testRunning = false
    @State private var testPeakDB: Float? = nil
    @State private var testStatus: String = ""

    var body: some View {
        Form {
            Section {
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
                        Text("Peak: \(Int(db.rounded())) dB · \(qualityLabel(db))")
                            .foregroundStyle(qualityColor(db))
                            .font(.callout.monospaced())
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
            } header: {
                Text("Microphone")
            } footer: {
                Text("Choose the input device used for dictation. The test records 1.5s and reports the peak level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { refreshDevices() }
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
