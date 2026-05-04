import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 560, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome:
            WelcomeStep()
        case .microphone:
            MicrophoneStep(viewModel: viewModel)
        case .accessibility:
            AccessibilityStep(viewModel: viewModel)
        case .model:
            ModelStep(viewModel: viewModel)
        case .done:
            DoneStep()
        }
    }

    private var footer: some View {
        HStack {
            stepIndicator
            Spacer()
            HStack(spacing: 10) {
                if viewModel.step != .welcome && viewModel.step != .done {
                    Button("Back") { viewModel.goBack() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(primaryActionLabel) {
                    if viewModel.step == .done {
                        onFinish()
                    } else {
                        viewModel.advance()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canAdvance)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == viewModel.step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var primaryActionLabel: LocalizedStringKey {
        switch viewModel.step {
        case .welcome: "Continue"
        case .microphone, .accessibility, .model: "Continue"
        case .done: "Finish"
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .foregroundStyle(LinearGradient(colors: [.indigo, .blue],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
            Text("Welcome to LocalWhisper")
                .font(.system(size: 24, weight: .bold))
            Text("Offline voice transcription on your Mac. We'll set up the three things the app needs to dictate everywhere: microphone access, the global hotkey, and the Whisper model.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

private struct MicrophoneStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            stepIcon(systemName: "mic.fill", color: .blue)
            Text("Microphone")
                .font(.system(size: 22, weight: .semibold))
            Text("LocalWhisper records audio locally to transcribe it. Audio never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            statusRow(
                granted: viewModel.microphoneGranted,
                grantedLabel: "Microphone access granted",
                missingLabel: "Microphone access not granted"
            )

            Button(viewModel.microphoneGranted ? "Re-check" : "Grant microphone access") {
                viewModel.requestMicrophonePermission()
            }
            .controlSize(.large)
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            stepIcon(systemName: "keyboard", color: .purple)
            Text("Accessibility")
                .font(.system(size: 22, weight: .semibold))
            Text("LocalWhisper needs Accessibility to capture the global hotkey (default: hold fn) and to paste the transcript into the active app. Open System Settings → Privacy & Security → Accessibility and enable LocalWhisper.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            statusRow(
                granted: viewModel.accessibilityGranted,
                grantedLabel: "Accessibility granted",
                missingLabel: "Accessibility not granted"
            )

            Button("Open System Settings") {
                viewModel.openAccessibilityPane()
            }
            .controlSize(.large)
        }
    }
}

private struct ModelStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 14) {
            stepIcon(systemName: "tray.and.arrow.down.fill", color: .green)
            Text("Whisper model")
                .font(.system(size: 22, weight: .semibold))

            Text("We'll download \(viewModel.recommendedModel.label) to ~/Library/Application Support/LocalWhisper/Models. The model runs entirely on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)

            if viewModel.modelInstalled {
                Label("Model installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else if viewModel.isDownloadingModel {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.modelDownloadProgress)
                        .frame(width: 320)
                    Text(viewModel.modelDownloadPhase.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel") { viewModel.cancelModelDownload() }
                    .controlSize(.small)
            } else {
                Button(downloadButtonLabel) {
                    Task { await viewModel.downloadRecommendedModel() }
                }
                .controlSize(.large)
            }

            if let err = viewModel.modelDownloadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var downloadButtonLabel: LocalizedStringKey {
        let mb = viewModel.recommendedModel.approxMB
        if HardwareProfile.current.isAppleSilicon,
           let coreMB = viewModel.recommendedModel.coreMLEncoderApproxMB {
            return "Download (\(mb) MB + \(coreMB) MB Core ML)"
        }
        return "Download (\(mb) MB)"
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
                .foregroundStyle(.green)
            Text("All set")
                .font(.system(size: 24, weight: .bold))
            Text("Hold fn anywhere on your Mac to dictate. Release to transcribe and auto-paste. The app lives in the menu bar — click the three bars to change settings or stop it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Shared bits

@ViewBuilder
private func stepIcon(systemName: String, color: Color) -> some View {
    ZStack {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: 84, height: 84)
        Image(systemName: systemName)
            .font(.system(size: 36))
            .foregroundStyle(color)
    }
}

@ViewBuilder
private func statusRow(granted: Bool, grantedLabel: LocalizedStringKey, missingLabel: LocalizedStringKey) -> some View {
    HStack(spacing: 8) {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(granted ? .green : .orange)
        Text(granted ? grantedLabel : missingLabel)
            .foregroundStyle(.secondary)
    }
    .padding(.top, 4)
}
