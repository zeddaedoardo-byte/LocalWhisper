import Foundation

enum PerformancePreset: String, CaseIterable, Identifiable {
    case quality
    case balanced
    case speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: L10n.string("Quality (most accurate)")
        case .balanced: L10n.string("Balanced")
        case .speed: L10n.string("Speed (fastest)")
        }
    }

    var description: String {
        switch self {
        case .quality: L10n.string("Quality preset description")
        case .balanced: L10n.string("Balanced preset description")
        case .speed: L10n.string("Speed preset description")
        }
    }

    var beamSize: Int {
        switch self {
        case .quality: 5
        case .balanced: 2
        case .speed: 1
        }
    }

    var bestOf: Int {
        switch self {
        case .quality: 5
        case .balanced: 2
        case .speed: 1
        }
    }

    /// Audio context for the encoder. 0 means full (1500). Truncating used to be
    /// a marginal speedup on the Speed preset, but pairing a truncated context
    /// (which silence-pads the encoder window) with a small decoder like Turbo
    /// and beam=1 produced deterministic hallucinations on short utterances:
    /// every sub-2 s recording converged on the same boilerplate string. Keeping
    /// the full audio context everywhere avoids the problem; the Speed preset is
    /// still faster than Balanced/Quality thanks to beam=1.
    var audioContext: Int {
        switch self {
        case .quality, .balanced, .speed: 0
        }
    }
}
