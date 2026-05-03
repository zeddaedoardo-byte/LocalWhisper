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
    @Published var hint: String = ""
    @Published private(set) var levelHistory: [Float]

    var levelDB: Float = -160 {
        didSet { pushLevel(levelDB) }
    }

    init(historySize: Int = 11) {
        self.levelHistory = Array(repeating: -160, count: historySize)
    }

    private func pushLevel(_ db: Float) {
        levelHistory.removeFirst()
        levelHistory.append(db)
    }
}

private let kHUDBarCount = 11
private let kHUDWidth: CGFloat = 140
private let kHUDHeight: CGFloat = 44

struct RecordingHUDView: View {
    @ObservedObject var viewModel: RecordingHUDViewModel

    var body: some View {
        ZStack {
            HUDVisualEffect(material: .hudWindow, cornerRadius: 14)

            WaveformView(
                state: viewModel.state,
                levels: viewModel.levelHistory
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: kHUDWidth, height: kHUDHeight)
    }
}

private struct WaveformView: View {
    let state: RecordingHUDState
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let count = max(levels.count, 1)
            let spacing: CGFloat = 3
            let barWidth = max(1, (width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(barFill(for: i))
                        .frame(width: barWidth, height: max(barWidth, barHeight(for: i, fullHeight: height)))
                        .animation(.easeOut(duration: 0.08), value: levels[i])
                }
            }
            .frame(width: width, height: height, alignment: .center)
        }
    }

    private func barHeight(for index: Int, fullHeight: CGFloat) -> CGFloat {
        switch state {
        case .recording:
            let normalized = normalize(levels[index])
            return CGFloat(0.18 + 0.82 * normalized) * fullHeight
        case .transcribing, .warmingUp:
            return shimmerHeight(index: index, fullHeight: fullHeight)
        case .completed, .error:
            return fullHeight * 0.22
        case .ready, .hidden:
            return fullHeight * 0.14
        }
    }

    private func shimmerHeight(index: Int, fullHeight: CGFloat) -> CGFloat {
        let phase = Date().timeIntervalSinceReferenceDate
        let wave = sin(phase * 4 + Double(index) * 0.6)
        let scaled = 0.45 + 0.35 * (0.5 + 0.5 * wave)
        return CGFloat(scaled) * fullHeight
    }

    private func normalize(_ db: Float) -> Double {
        let clamped = max(-60, min(0, db))
        return Double((clamped + 60) / 60)
    }

    private func barFill(for index: Int) -> LinearGradient {
        let colors: [Color]
        switch state {
        case .recording:
            colors = [Color.red.opacity(0.95), Color.pink.opacity(0.85)]
        case .transcribing, .warmingUp:
            colors = [Color.blue.opacity(0.9), Color.cyan.opacity(0.85)]
        case .completed:
            colors = [Color.green.opacity(0.9), Color.mint.opacity(0.85)]
        case .error:
            colors = [Color.orange.opacity(0.9), Color.yellow.opacity(0.85)]
        case .ready, .hidden:
            colors = [Color.secondary.opacity(0.45), Color.secondary.opacity(0.35)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
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
            contentRect: NSRect(x: 0, y: 0, width: kHUDWidth, height: kHUDHeight),
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
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.invalidateShadow()
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
