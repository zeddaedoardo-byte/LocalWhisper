import AppKit
import Foundation

@MainActor
final class SoundService {
    static let shared = SoundService()

    var isEnabled: Bool = true

    func playStartListening() {
        guard isEnabled else { return }
        play(named: "Tink")
    }

    func playStopListening() {
        guard isEnabled else { return }
        play(named: "Pop")
    }

    private func play(named name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.4
        sound.play()
    }
}
