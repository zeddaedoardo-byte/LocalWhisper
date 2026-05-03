import SwiftUI

struct HotkeySettingsTab: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Trigger", selection: $settings.pushToTalkTriggerID) {
                    ForEach(PushToTalkTrigger.all) { trigger in
                        Text(trigger.label).tag(trigger.id)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Spacer()
                    KeyCapView(label: PushToTalkTrigger.byID(settings.pushToTalkTriggerID).label)
                    Spacer()
                }
                .padding(.vertical, 12)

                Text("Hold the key (or combo) to record. Release to transcribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Push-to-talk")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct KeyCapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}
