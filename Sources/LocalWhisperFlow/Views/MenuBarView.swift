import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if let warning = warningMessage {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            if !appState.lastTranscript.isEmpty {
                Divider()
                transcriptSection
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            Divider()

            actions
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: appState.status.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(triggerHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ultima trascrizione")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    appState.copyLastTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Copia trascritto")
            }
            Text(appState.lastTranscript)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            MenuRow(
                icon: appState.status == .recording ? "stop.fill" : "mic.fill",
                label: appState.status.primaryActionTitle,
                disabled: !appState.status.canToggleRecording,
                action: appState.toggleRecording
            )

            MenuToggleRow(
                icon: "doc.on.clipboard",
                label: "Auto Paste",
                isOn: $settings.autoPaste
            )

            if !appState.hasAccessibility {
                MenuRow(
                    icon: "lock.open",
                    label: "Concedi Accessibility...",
                    action: {
                        appState.requestAccessibilityPermission()
                        openAccessibilitySettings()
                    }
                )
            }

            Divider().padding(.vertical, 4)

            MenuRow(
                icon: "gearshape",
                label: "Settings...",
                action: {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            )

            MenuRow(
                icon: "power",
                label: "Esci",
                shortcut: "⌘Q",
                action: { NSApp.terminate(nil) }
            )
        }
    }

    private var statusTint: Color {
        switch appState.status {
        case .idle: appState.isServerReady ? .green : .secondary
        case .recording: .red
        case .transcribing: .blue
        case .completed: .green
        case .failed: .orange
        }
    }

    private var statusTitle: String {
        switch appState.status {
        case .idle: "Pronto"
        case .recording: "Registrazione"
        case .transcribing: "Trascrizione"
        case .completed: "Pronto"
        case .failed: "Errore"
        }
    }

    private var triggerHint: String {
        let trigger = PushToTalkTrigger.byID(settings.pushToTalkTriggerID)
        return "Tieni \(trigger.label) per dettare"
    }

    private var warningMessage: String? {
        if !appState.hasAccessibility {
            return "Accessibility non concessa"
        }
        if appState.isWarmingUp {
            return "Caricamento modello..."
        }
        if !appState.isServerReady && !appState.isWarmingUp {
            return "Server fermo"
        }
        return nil
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    var shortcut: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(disabled ? .secondary : .primary)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? .secondary : .primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovered && !disabled ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 }
    }
}

private struct MenuToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    @State private var hovered = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .controlSize(.small)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovered ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
