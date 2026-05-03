import Foundation

enum PerformancePreset: String, CaseIterable, Identifiable {
    case quality
    case balanced
    case speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: String(localized: "Quality (most accurate)")
        case .balanced: String(localized: "Balanced")
        case .speed: String(localized: "Speed (fastest)")
        }
    }

    var description: String {
        switch self {
        case .quality: String(localized: "Quality preset description")
        case .balanced: String(localized: "Balanced preset description")
        case .speed: String(localized: "Speed preset description")
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
