import ApplicationServices
import AppKit

enum PushToTalkError: LocalizedError {
    case accessibilityPermissionRequired
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required for global Control push-to-talk."
        case .eventTapCreationFailed:
            "Could not create the global Control push-to-talk event tap."
        }
    }
}

enum PushToTalkTransition: Equatable {
    case pressed
    case released
}

struct PushToTalkStateMachine {
    private(set) var isControlPressed = false

    mutating func update(controlIsPressed: Bool) -> PushToTalkTransition? {
        guard controlIsPressed != isControlPressed else { return nil }
        isControlPressed = controlIsPressed
        return controlIsPressed ? .pressed : .released
    }

    mutating func reset() {
        isControlPressed = false
    }
}

final class PushToTalkService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = PushToTalkStateMachine()
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    deinit {
        stop()
    }

    func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) throws {
        stop()
        self.onPress = onPress
        self.onRelease = onRelease

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            throw PushToTalkError.accessibilityPermissionRequired
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw PushToTalkError.eventTapCreationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        stateMachine.reset()
    }

    private func dispatchHandle(controlIsPressed: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(controlIsPressed: controlIsPressed)
        }
    }

    private func handle(controlIsPressed: Bool) {
        guard let transition = stateMachine.update(controlIsPressed: controlIsPressed) else {
            return
        }

        switch transition {
        case .pressed:
            onPress?()
        case .released:
            onRelease?()
        }
    }

    private func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        AXIsProcessTrustedWithOptions(options)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<PushToTalkService>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                service.reenableEventTap()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        service.dispatchHandle(controlIsPressed: event.flags.contains(.maskControl))
        return Unmanaged.passUnretained(event)
    }
}
