import AppKit
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
            Image(nsImage: MenuBarIconRenderer.shared.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(appState)
        }
    }
}

private final class MenuBarIconRenderer {
    static let shared = MenuBarIconRenderer()

    let image: NSImage

    private init() {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let bars: [(x: CGFloat, h: CGFloat)] = [
                (3.5, 7),
                (8.0, 15),
                (12.5, 10)
            ]
            NSColor.black.setFill()
            for bar in bars {
                let barRect = NSRect(
                    x: bar.x - 1.25,
                    y: (size.height - bar.h) / 2,
                    width: 2.5,
                    height: bar.h
                )
                NSBezierPath(roundedRect: barRect, xRadius: 1.25, yRadius: 1.25).fill()
            }
            return true
        }
        img.isTemplate = true
        self.image = img
    }
}
