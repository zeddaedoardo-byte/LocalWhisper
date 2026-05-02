import AppKit
import SwiftUI

enum RecordingHUDState: Equatable {
    case hidden
    case warmingUp
    case ready
    case recording
    case transcribing
    case completed
    case error(String)

    var title: String {
        switch self {
        case .hidden, .ready: "Ready - hold fn"
        case .warmingUp: "Warming up Whisper..."
        case .recording: "Recording"
        case .transcribing: "Transcribing..."
        case .completed: "Done"
        case .error(let msg): msg
        }
    }
}

@MainActor
final class RecordingHUDViewModel: ObservableObject {
    @Published var state: RecordingHUDState = .hidden
    @Published var levelDB: Float = -160
    @Published var hint: String = ""
    @Published var diagnostic: String = ""
}

struct RecordingHUDView: View {
    @ObservedObject var viewModel: RecordingHUDViewModel

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                levelBar
                    .frame(height: 6)

                if !viewModel.hint.isEmpty {
                    Text(viewModel.hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                if !viewModel.diagnostic.isEmpty {
                    Text(viewModel.diagnostic)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, height: 76)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch viewModel.state {
        case .recording:
            TimelineView(.animation) { context in
                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSince1970 * 4)
                Circle()
                    .fill(Color.red)
                    .opacity(0.4 + 0.6 * pulse)
            }
        case .transcribing, .warmingUp:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .foregroundStyle(.orange)
        case .ready, .hidden:
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var levelBar: some View {
        GeometryReader { geo in
            let normalized = CGFloat(max(0, min(1, (viewModel.levelDB + 50) / 50)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(levelColor)
                    .frame(width: geo.size.width * normalized)
                    .animation(.easeOut(duration: 0.08), value: normalized)
            }
        }
    }

    private var levelColor: Color {
        switch viewModel.state {
        case .recording: .green
        case .transcribing, .warmingUp: .blue
        case .error: .orange
        case .completed: .green
        case .ready, .hidden: .white.opacity(0.4)
        }
    }
}

@MainActor
final class RecordingHUDController {
    private let viewModel = RecordingHUDViewModel()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func update(state: RecordingHUDState, hint: String = "") {
        viewModel.state = state
        viewModel.hint = hint
        cancelScheduledHide()
        ensureVisible()
    }

    func update(diagnostic: String) {
        viewModel.diagnostic = diagnostic
    }

    func update(levelDB: Float) {
        viewModel.levelDB = levelDB
    }

    private func ensureVisible() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        if !panel.isVisible {
            positionPanel(panel)
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        cancelScheduledHide()
        if seconds <= 0 {
            panel?.orderOut(nil)
            return
        }
        let item = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func createPanel() {
        let host = NSHostingView(rootView: RecordingHUDView(viewModel: viewModel))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = host
        positionPanel(panel)
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
