import AppKit

final class PushToTalkService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isControlPressed = false
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    deinit {
        stop()
    }

    func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        stop()
        self.onPress = onPress
        self.onRelease = onRelease

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.dispatchHandle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.dispatchHandle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isControlPressed = false
    }

    private func dispatchHandle(_ event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let controlIsPressed = flags.contains(.control)

        guard controlIsPressed != isControlPressed else { return }
        isControlPressed = controlIsPressed

        DispatchQueue.main.async { [onPress, onRelease] in
            if controlIsPressed {
                onPress?()
            } else {
                onRelease?()
            }
        }
    }
}
