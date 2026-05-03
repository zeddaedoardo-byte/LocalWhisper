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

    /// Audio context for the encoder. 0 means full (1500). Smaller = faster but
    /// risks truncating long utterances.
    var audioContext: Int {
        switch self {
        case .quality: 0
        case .balanced: 0
        case .speed: 768
        }
    }
}
