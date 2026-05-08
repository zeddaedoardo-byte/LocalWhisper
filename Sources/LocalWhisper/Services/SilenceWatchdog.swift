import Combine
import Foundation

/// Auto-stop helper for the continuous (double-tap) recording mode.
/// Subscribes to `AudioRecorderService.$levelDB`, requires a short
/// "arming" period of detected speech to avoid stopping on dead-air,
/// and fires `onSilence` once silence has lasted `silenceDuration`.
@MainActor
final class SilenceWatchdog {
    static let thresholdDB: Float = -45
    static let silenceDuration: TimeInterval = 2.0
    static let armingDuration: TimeInterval = 0.5
    private static let tickInterval: TimeInterval = 0.1

    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var lastLevel: Float = -160
    private var speechStreak: TimeInterval = 0
    private var silenceStreak: TimeInterval = 0
    private var armed = false
    private var onSilence: (() -> Void)?

    func start(level: AnyPublisher<Float, Never>, onSilence: @escaping () -> Void) {
        stop()
        self.onSilence = onSilence
        cancellable = level.sink { [weak self] db in
            self?.lastLevel = db
        }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellable?.cancel()
        cancellable = nil
        onSilence = nil
        armed = false
        speechStreak = 0
        silenceStreak = 0
        lastLevel = -160
    }

    private func evaluate() {
        if lastLevel >= Self.thresholdDB {
            speechStreak += Self.tickInterval
            silenceStreak = 0
            if !armed, speechStreak >= Self.armingDuration {
                armed = true
            }
        } else if armed {
            silenceStreak += Self.tickInterval
            if silenceStreak >= Self.silenceDuration {
                let callback = onSilence
                stop()
                callback?()
            }
        }
    }
}
