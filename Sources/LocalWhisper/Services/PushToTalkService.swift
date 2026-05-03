import ApplicationServices
import AppKit
import Carbon.HIToolbox
import os.log

enum PushToTalkError: LocalizedError {
    case accessibilityPermissionRequired
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required for global fn push-to-talk."
        case .eventTapCreationFailed:
            "Could not create the global fn push-to-talk event tap."
        }
    }
}


enum PushToTalkTransition: Equatable {
    case pressed
    case released
}

struct PushToTalkStateMachine {
    private(set) var isTriggerPressed = false

    mutating func update(triggerIsPressed: Bool) -> PushToTalkTransition? {
        guard triggerIsPressed != isTriggerPressed else { return nil }
        isTriggerPressed = triggerIsPressed
        return triggerIsPressed ? .pressed : .released
    }

    mutating func reset() {
        isTriggerPressed = false
    }
}

private let pttLog = Logger(subsystem: "com.local.LocalWhisper", category: "ptt")

enum PttDebugLog {
    private static let lock = NSLock()
    private static let path = "/tmp/lwf-ptt.log"

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }
}

final class PushToTalkService {
    nonisolated(unsafe) private static var totalEventsReceived: Int = 0
    nonisolated(unsafe) private static var lastFlagsRaw: UInt64 = 0
    nonisolated(unsafe) private static var lastKeycode: Int = -1
    private static let counterLock = NSLock()

    static func currentEventCount() -> Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return totalEventsReceived
    }

    static func currentLastFlagsRaw() -> UInt64 {
        counterLock.lock()
        defer { counterLock.unlock() }
        return lastFlagsRaw
    }

    static func currentLastKeycode() -> Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return lastKeycode
    }

    private static func bumpCounter(flagsRaw: UInt64, keycode: Int) {
        counterLock.lock()
        totalEventsReceived &+= 1
        lastFlagsRaw = flagsRaw
        lastKeycode = keycode
        counterLock.unlock()
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = PushToTalkStateMachine()
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    nonisolated(unsafe) private static var currentTrigger: PushToTalkTrigger = .fn
    private static let triggerLock = NSLock()

    static func setTrigger(_ trigger: PushToTalkTrigger) {
        triggerLock.lock()
        currentTrigger = trigger
        triggerLock.unlock()
    }

    static func activeTrigger() -> PushToTalkTrigger {
        triggerLock.lock()
        defer { triggerLock.unlock() }
        return currentTrigger
    }

    deinit {
        stop()
    }

    func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) throws {
        stop()
        self.onPress = onPress
        self.onRelease = onRelease

        let trusted = AXIsProcessTrusted()
        PttDebugLog.write("ptt.start trusted=\(trusted)")
        guard trusted else {
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
            pttLog.error("ptt.tapCreate FAILED")
            throw PushToTalkError.eventTapCreationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        PttDebugLog.write("ptt.tapCreate OK, tap enabled")

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

    private func dispatchHandle(triggerIsPressed: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(triggerIsPressed: triggerIsPressed)
        }
    }

    private func handle(triggerIsPressed: Bool) {
        guard let transition = stateMachine.update(triggerIsPressed: triggerIsPressed) else {
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

        let flagsRaw = UInt64(event.flags.rawValue)
        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        PushToTalkService.bumpCounter(flagsRaw: flagsRaw, keycode: keycode)

        let trigger = PushToTalkService.activeTrigger()
        if let pressed = trigger.evaluate(flagsRaw: flagsRaw, keycode: keycode) {
            PttDebugLog.write("ptt.event kc=\(keycode) flags=0x\(String(flagsRaw, radix: 16)) trig=\(trigger.id) pressed=\(pressed)")
            service.dispatchHandle(triggerIsPressed: pressed)
        }
        return Unmanaged.passUnretained(event)
    }
}
