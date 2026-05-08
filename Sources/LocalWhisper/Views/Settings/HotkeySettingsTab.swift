import AppKit
import SwiftUI

struct HotkeySettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore

    private enum CaptureTarget { case primary, lock }

    @State private var capturing = false
    @State private var captureTarget: CaptureTarget = .primary
    @State private var captureMonitor: Any?
    @State private var captureMask: UInt64 = 0
    @State private var captureKeycode: Int = -1
    @State private var captureCommitWorkItem: DispatchWorkItem?

    var body: some View {
        Form {
            Section {
                Picker("Default trigger", selection: $settings.pushToTalkTriggerID) {
                    ForEach(PushToTalkTrigger.all) { trigger in
                        Text(trigger.label).tag(trigger.id)
                    }
                    if isCustomConfigured {
                        Text("Custom: \(customLabel)").tag("custom")
                    }
                }
                .pickerStyle(.menu)
                .disabled(capturing)

                HStack {
                    Spacer()
                    KeyCapView(label: activeLabel, highlight: capturing)
                    Spacer()
                }
                .padding(.vertical, 12)

                Button(primaryCaptureButtonLabel) {
                    if capturing && captureTarget == .primary {
                        cancelCapture()
                    } else {
                        startCapture(target: .primary)
                    }
                }
                .keyboardShortcut(.defaultAction)

                Text("Press and hold the key (or combo) you want. Release to confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Push-to-talk")
            }

            if isCustomConfigured {
                Section {
                    HStack {
                        Text("Current hotkey")
                        Spacer()
                        Text(customLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(String(format: "Keycode %d, flags 0x%llx",
                                    settings.customTriggerKeycode,
                                    settings.customTriggerFlags))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove custom") {
                            clearCustom()
                        }
                    }
                } header: {
                    Text("Custom")
                }
            }

            Section {
                Picker("Lock-in hotkey", selection: $settings.lockTriggerID) {
                    Text("Off").tag("")
                    ForEach(PushToTalkTrigger.all) { trigger in
                        Text(trigger.label).tag(trigger.id)
                    }
                    if isCustomLockConfigured {
                        Text("Custom: \(customLockLabel)").tag("custom")
                    }
                }
                .pickerStyle(.menu)
                .disabled(capturing)

                HStack {
                    Spacer()
                    KeyCapView(label: lockActiveLabel, highlight: capturing && captureTarget == .lock)
                    Spacer()
                }
                .padding(.vertical, 12)

                Button(lockCaptureButtonLabel) {
                    if capturing && captureTarget == .lock {
                        cancelCapture()
                    } else {
                        startCapture(target: .lock)
                    }
                }

                Text("Tap this combo while idle (or while holding the primary trigger) to start a hands-free continuous recording. Tap again — or stay silent ~2 seconds — to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Continuous lock")
            }

            if isCustomLockConfigured {
                Section {
                    HStack {
                        Text("Current lock hotkey")
                        Spacer()
                        Text(customLockLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(String(format: "Keycode %d, flags 0x%llx",
                                    settings.customLockTriggerKeycode,
                                    settings.customLockTriggerFlags))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove custom lock") {
                            clearCustomLock()
                        }
                    }
                } header: {
                    Text("Lock custom")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onDisappear { cancelCapture() }
    }

    private var isCustomConfigured: Bool {
        settings.customTriggerKeycode >= 0 && settings.customTriggerFlags != 0
    }

    private var customLabel: String {
        settings.customTriggerLabel.isEmpty
            ? PushToTalkTrigger.describe(keycode: settings.customTriggerKeycode,
                                         flags: settings.customTriggerFlags)
            : settings.customTriggerLabel
    }

    private var activeLabel: String {
        if capturing && captureTarget == .primary {
            if captureMask != 0 {
                return PushToTalkTrigger.describe(keycode: captureKeycode, flags: captureMask)
            }
            return "..."
        }
        if settings.pushToTalkTriggerID == "custom", isCustomConfigured {
            return customLabel
        }
        return PushToTalkTrigger.byID(settings.pushToTalkTriggerID).label
    }

    private var primaryCaptureButtonLabel: String {
        capturing && captureTarget == .primary
            ? "Listening… press and release"
            : "Capture key from keyboard"
    }

    private var isCustomLockConfigured: Bool {
        settings.customLockTriggerKeycode >= 0 && settings.customLockTriggerFlags != 0
    }

    private var customLockLabel: String {
        settings.customLockTriggerLabel.isEmpty
            ? PushToTalkTrigger.describe(keycode: settings.customLockTriggerKeycode,
                                         flags: settings.customLockTriggerFlags)
            : settings.customLockTriggerLabel
    }

    private var lockActiveLabel: String {
        if capturing && captureTarget == .lock {
            if captureMask != 0 {
                return PushToTalkTrigger.describe(keycode: captureKeycode, flags: captureMask)
            }
            return "..."
        }
        if settings.lockTriggerID.isEmpty {
            return "Off"
        }
        if settings.lockTriggerID == "custom", isCustomLockConfigured {
            return customLockLabel
        }
        return PushToTalkTrigger.byID(settings.lockTriggerID).label
    }

    private var lockCaptureButtonLabel: String {
        capturing && captureTarget == .lock
            ? "Listening… press and release"
            : "Capture lock combo from keyboard"
    }

    private func startCapture(target: CaptureTarget) {
        // If a different capture is already running, swap it cleanly.
        if capturing { cancelCapture() }
        capturing = true
        captureTarget = target
        captureMask = 0
        captureKeycode = -1
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleCapture(event: event)
            return nil
        }
        captureMonitor = monitor
    }

    private func handleCapture(event: NSEvent) {
        let raw = UInt64(event.modifierFlags.rawValue) & 0x00FFFFFF
        if raw != 0 {
            captureMask |= raw
            captureKeycode = Int(event.keyCode)
            scheduleCommit()
        } else if captureMask != 0 {
            commitCapture()
        }
    }

    private func scheduleCommit() {
        captureCommitWorkItem?.cancel()
        let item = DispatchWorkItem { commitCapture() }
        captureCommitWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func commitCapture() {
        guard capturing else { return }
        captureCommitWorkItem?.cancel()
        captureCommitWorkItem = nil
        if let m = captureMonitor { NSEvent.removeMonitor(m) }
        captureMonitor = nil
        let target = captureTarget
        capturing = false

        guard captureMask != 0 else { return }
        let label = PushToTalkTrigger.describe(keycode: captureKeycode, flags: captureMask)
        switch target {
        case .primary:
            settings.customTriggerKeycode = captureKeycode
            settings.customTriggerFlags = captureMask
            settings.customTriggerLabel = label
            settings.pushToTalkTriggerID = "custom"
        case .lock:
            settings.customLockTriggerKeycode = captureKeycode
            settings.customLockTriggerFlags = captureMask
            settings.customLockTriggerLabel = label
            settings.lockTriggerID = "custom"
        }
    }

    private func cancelCapture() {
        captureCommitWorkItem?.cancel()
        captureCommitWorkItem = nil
        if let m = captureMonitor { NSEvent.removeMonitor(m) }
        captureMonitor = nil
        capturing = false
        captureMask = 0
        captureKeycode = -1
    }

    private func clearCustom() {
        settings.customTriggerKeycode = -1
        settings.customTriggerFlags = 0
        settings.customTriggerLabel = ""
        settings.pushToTalkTriggerID = PushToTalkTrigger.fn.id
    }

    private func clearCustomLock() {
        settings.customLockTriggerKeycode = -1
        settings.customLockTriggerFlags = 0
        settings.customLockTriggerLabel = ""
        if settings.lockTriggerID == "custom" {
            settings.lockTriggerID = ""
        }
    }
}

private struct KeyCapView: View {
    let label: String
    var highlight: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(highlight ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlight ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}
