import AppKit
import SwiftUI

enum RecordingHUDState: Equatable {
    case hidden
    case warmingUp
    case ready
    case recording
    case transcribing
    case completed(String)
    case error(String)
}

@MainActor
final class RecordingHUDViewModel: ObservableObject {
    @Published var state: RecordingHUDState = .hidden
    @Published var levelDB: Float = -160
    @Published var hint: String = ""
}

private let kHUDBarCount = 7

struct RecordingHUDView: View {
    @ObservedObject var viewModel: RecordingHUDViewModel

    var body: some View {
        ZStack {
            HUDVisualEffect(material: .hudWindow)

            HStack(spacing: 14) {
                indicator
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    EqualizerView(state: viewModel.state, levelDB: viewModel.levelDB)
                        .frame(height: 16)

                    if !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 300, height: 76)
    }

    private var title: String {
        switch viewModel.state {
        case .hidden: ""
        case .warmingUp: "Caricamento..."
        case .ready: "Pronto"
        case .recording: "Registrazione"
        case .transcribing: "Trascrizione"
        case .completed: "Fatto"
        case .error: "Errore"
        }
    }

    private var hint: String {
        if case .completed(let preview) = viewModel.state, !preview.isEmpty {
            return preview
        }
        if case .error(let message) = viewModel.state, !message.isEmpty {
            return message
        }
        return viewModel.hint
    }

    @ViewBuilder
    private var indicator: some View {
        switch viewModel.state {
        case .recording:
            TimelineView(.animation) { context in
                let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSince1970 * 5)
                Circle()
                    .fill(Color.red)
                    .opacity(0.55 + 0.45 * pulse)
                    .overlay(
                        Circle().stroke(Color.red.opacity(0.35), lineWidth: 3)
                            .scaleEffect(1 + CGFloat(pulse) * 0.18)
                    )
            }
        case .transcribing, .warmingUp:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
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
                .foregroundStyle(.secondary)
        }
    }
}

private struct EqualizerView: View {
    let state: RecordingHUDState
    let levelDB: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<kHUDBarCount, id: \.self) { index in
                    bar(for: index, phase: phase)
                }
            }
        }
    }

    private func bar(for index: Int, phase: TimeInterval) -> some View {
        GeometryReader { geo in
            let height = geo.size.height
            let amplitude = barAmplitude(index: index, phase: phase)
            let h = max(2, CGFloat(amplitude) * height)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barColor)
                .frame(height: h)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barAmplitude(index: Int, phase: TimeInterval) -> Double {
        switch state {
        case .recording:
            let normalized = max(0, min(1, Double((levelDB + 50) / 50)))
            let envelope = 0.4 + 0.6 * normalized
            let wave = sin(phase * 6 + Double(index) * 0.7)
            let jitter = 0.5 + 0.5 * wave
            return envelope * (0.35 + 0.65 * jitter)
        case .transcribing, .warmingUp:
            let wave = sin(phase * 4 + Double(index) * 0.9)
            return 0.35 + 0.35 * (0.5 + 0.5 * wave)
        case .completed:
            return 0.25
        case .error:
            return 0.20
        case .ready, .hidden:
            return 0.12
        }
    }

    private var barColor: Color {
        switch state {
        case .recording: .red
        case .transcribing, .warmingUp: .blue
        case .completed: .green
        case .error: .orange
        case .ready, .hidden: .secondary
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

        switch state {
        case .recording, .transcribing:
            cancelScheduledHide()
            show()
        case .completed:
            cancelScheduledHide()
            show()
            scheduleHide(after: 1.2)
        case .error:
            cancelScheduledHide()
            show()
            scheduleHide(after: 3.0)
        case .warmingUp, .ready, .hidden:
            cancelScheduledHide()
            hide()
        }
    }

    func update(levelDB: Float) {
        viewModel.levelDB = levelDB
    }

    private func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        positionPanel(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func scheduleHide(after seconds: TimeInterval) {
        cancelScheduledHide()
        let item = DispatchWorkItem { [weak self] in
            self?.hide()
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
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
        panel.isMovable = false
        panel.contentView = host
        positionPanel(panel)
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen = targetScreen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 100
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
