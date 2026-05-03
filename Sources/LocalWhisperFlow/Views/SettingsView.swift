import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            WhisperSettingsTab()
                .tabItem { Label("Whisper", systemImage: "waveform") }

            MicrophoneSettingsTab()
                .tabItem { Label("Microphone", systemImage: "mic") }

            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            OutputSettingsTab()
                .tabItem { Label("Output", systemImage: "doc.on.clipboard") }

            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 480)
    }
}
