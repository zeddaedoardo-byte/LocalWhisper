import AppKit
import Carbon.HIToolbox

@MainActor
final class EscapeKeyMonitor {
    private var monitor: Any?
    private var onEscape: (() -> Void)?

    var isActive: Bool { monitor != nil }

    func start(onEscape: @escaping () -> Void) {
        stop()
        self.onEscape = onEscape
        let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == kVK_Escape else { return }
            Task { @MainActor in
                self?.onEscape?()
            }
        }
        self.monitor = m
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
        monitor = nil
        onEscape = nil
    }
}
