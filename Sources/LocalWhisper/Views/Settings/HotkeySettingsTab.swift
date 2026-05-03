import AppKit
import SwiftUI

struct HotkeySettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore

    @State private var capturing = false
    @State private var captureMonitor: Any?
    @State private var captureMask: UInt64 = 0
    @State private var captureKeycode: Int = -1
    @State private var captureCommitWorkItem: DispatchWorkItem?

    var body: some View {
        Form {
            Section {
                Picker("Trigger predefinito", selection: $settings.pushToTalkTriggerID) {
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

                Button(capturing ? "In ascolto... premi e rilascia" : "Cattura tasto da tastiera") {
                    if capturing {
                        cancelCapture()
                    } else {
                        startCapture()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Text("Premi e tieni il tasto (o la combinazione) che vuoi usare. Rilascia per confermare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Push-to-talk")
            }

            if isCustomConfigured {
                Section {
                    HStack {
                        Text("Hotkey corrente")
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
                        Button("Rimuovi custom") {
                            clearCustom()
                        }
                    }
                } header: {
                    Text("Custom")
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
        if capturing {
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

    private func startCapture() {
        capturing = true
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
        capturing = false

        guard captureMask != 0 else { return }
        let label = PushToTalkTrigger.describe(keycode: captureKeycode, flags: captureMask)
        settings.customTriggerKeycode = captureKeycode
        settings.customTriggerFlags = captureMask
        settings.customTriggerLabel = label
        settings.pushToTalkTriggerID = "custom"
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
