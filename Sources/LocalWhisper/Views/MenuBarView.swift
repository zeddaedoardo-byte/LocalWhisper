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

            if let label = timeSavedLabel {
                timeSavedBanner(label)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
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
            promptSection
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()
            llmRefinementSection
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            actions
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
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
                Text("Last transcript")
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
                .help("Copy transcript")
            }
            Text(appState.lastTranscript)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var promptSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $settings.initialPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1)
                    )

                Text("Add words you say often that Whisper gets wrong: brand names, technical terms, acronyms. Bias only — Whisper still transcribes what you actually say. Keep it short (under ~150 words). Leave empty to disable.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !settings.initialPrompt.isEmpty {
                    Button {
                        settings.initialPrompt = ""
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Dictation hints")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if !settings.initialPrompt.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private var llmRefinementSection: some View {
        // Quick toggle in the menu bar; full management (model picker,
        // download, paths) lives in Settings → LLM.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("LLM refinement")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if settings.llmRefinementEnabled && !settings.llmModelPath.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Toggle("", isOn: $settings.llmRefinementEnabled)
                    .labelsHidden()
                    .controlSize(.small)
                    .toggleStyle(.switch)
                    .disabled(!llmReady)
            }
            if !llmReady {
                Text("Configure model in Settings → LLM")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                if settings.llmRefinementEnabled {
                    HStack(spacing: 6) {
                        Text("Style:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { settings.llmRefinementStyle },
                            set: { settings.llmRefinementStyle = $0 }
                        )) {
                            Text("Light").tag(SettingsStore.RefinementStyle.light)
                            Text("Polish").tag(SettingsStore.RefinementStyle.polish)
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .pickerStyle(.segmented)
                    }
                }
                if let modelName = currentLlmModelName {
                    Text(modelName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var llmReady: Bool {
        !settings.llmServerBinaryPath.isEmpty &&
        FileManager.default.isExecutableFile(atPath: settings.llmServerBinaryPath) &&
        !settings.llmModelPath.isEmpty &&
        FileManager.default.fileExists(atPath: settings.llmModelPath)
    }

    private var currentLlmModelName: String? {
        guard !settings.llmModelPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: settings.llmModelPath)
        return url.deletingPathExtension().lastPathComponent
    }

    private func timeSavedBanner(_ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
                Text("saved vs typing")
                    .font(.system(size: 10))
                    .foregroundStyle(.green.opacity(0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var timeSavedLabel: String? {
        let total = settings.totalTimeSavedSeconds
        guard total >= 1 else { return nil }
        if total < 60 {
            return "\(Int(total)) sec"
        }
        let minutes = Int(total / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h) h \(m) min" : "\(h) h"
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
                    label: "Grant Accessibility…",
                    action: {
                        appState.requestAccessibilityPermission()
                        openAccessibilitySettings()
                    }
                )
            }

            MenuRow(
                icon: "arrow.clockwise",
                label: "Restart engine",
                action: { appState.restartPipeline() }
            )

            Divider().padding(.vertical, 4)

            MenuRow(
                icon: "gearshape",
                label: "Settings…",
                action: {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            )

            MenuRow(
                icon: "power",
                label: "Quit",
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

    private var statusTitle: LocalizedStringKey {
        switch appState.status {
        case .idle: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .completed: "Ready"
        case .failed: "Error"
        }
    }

    private var triggerHint: LocalizedStringKey {
        let trigger = PushToTalkTrigger.byID(settings.pushToTalkTriggerID)
        return "Hold \(trigger.label) to dictate"
    }

    private var warningMessage: LocalizedStringKey? {
        if !appState.hasAccessibility {
            return "Accessibility not granted"
        }
        if appState.isWarmingUp {
            return "Loading model…"
        }
        if !appState.isServerReady && !appState.isWarmingUp {
            return "Server stopped"
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
    let label: LocalizedStringKey
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
    let label: LocalizedStringKey
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
