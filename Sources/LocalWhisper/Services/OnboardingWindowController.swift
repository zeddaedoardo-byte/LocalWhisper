import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var viewModel: OnboardingViewModel?
    private var onClose: (() -> Void)?

    func show(onClose: (() -> Void)? = nil) {
        self.onClose = onClose

        if window == nil {
            let viewModel = OnboardingViewModel()
            self.viewModel = viewModel

            let view = OnboardingView(viewModel: viewModel) { [weak self] in
                self?.close()
            }
            let host = NSHostingController(rootView: view)
            let panel = NSWindow(contentViewController: host)
            panel.title = "LocalWhisper Setup"
            panel.styleMask = [.titled, .closable]
            panel.isReleasedWhenClosed = false
            panel.center()
            self.window = panel
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
        viewModel = nil
        // Drop the activation policy back to .accessory so the app returns to
        // being a pure menu-bar resident.
        NSApp.setActivationPolicy(.accessory)
        let cb = onClose
        onClose = nil
        cb?()
    }
}
