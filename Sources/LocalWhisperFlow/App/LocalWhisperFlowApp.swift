import SwiftUI

@main
struct LocalWhisperFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var appState: AppState

    init() {
        let settingsStore = SettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _appState = StateObject(wrappedValue: AppState(settings: settingsStore))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(settings)
                .environmentObject(appState)
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(appState)
        }
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if #available(macOS 14, *) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .symbolEffect(.variableColor.iterative.reversing,
                              isActive: shouldAnimate)
        } else {
            Image(systemName: symbol)
        }
    }

    private var symbol: String {
        switch appState.status {
        case .recording: "record.circle.fill"
        case .transcribing: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .idle:
            if appState.isWarmingUp { "mic.badge.ellipsis" }
            else if appState.isServerReady { "mic.fill" }
            else { "mic" }
        }
    }

    private var shouldAnimate: Bool {
        switch appState.status {
        case .recording, .transcribing: true
        case .idle: appState.isWarmingUp
        default: false
        }
    }
}
